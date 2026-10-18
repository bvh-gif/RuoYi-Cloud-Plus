#!/usr/bin/env bash
# 一键重建整套环境（幂等：已做过的步骤会自动跳过）
#
# 环境：Git Bash / WSL / 任意能连 desktop-linux 的 docker CLI
#
# ── 解决什么问题 ────────────────────────────────────────────────────
# 这套环境此前是「手工一步步堆出来的状态」，不是「代码」：
# 建库、导表、bootstrap Nacos 管理员、导配置、起服务——步骤只存在于人的记忆里。
# 换机器 / 清掉 .local-data / 换人接手，就得靠人肉重走一遍，很容易漏。
# 本脚本把这些全部固化下来，且保证重复执行安全。
#
# ── 用法 ────────────────────────────────────────────────────────────
#   ./script/bootstrap.sh              # 重建到「可起服务」的状态
#   ./script/bootstrap.sh --with-stack # 顺便把最小集（3 个核心服务）也起来
#
# ── 幂等性保证 ──────────────────────────────────────────────────────
#   建库     CREATE DATABASE IF NOT EXISTS
#   导表     表数 > 0 则跳过（不会重复导入、不会覆盖数据）
#   管理员   能登录就跳过（bootstrap 端点是一次性的，调过就不能再调）
#   导配置   覆盖写入，天然幂等
#
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

MYSQL_C="${MYSQL_C:-mysql}"
NACOS_C="${NACOS_C:-nacos}"
DB_USER="${DB_USER:-root}"
DB_PASS="${DB_PASS:-ruoyi123}"
NACOS_API="http://127.0.0.1:8848"
NACOS_USER="${NACOS_USER:-nacos}"
NACOS_PASS="${NACOS_PASS:-ruoyi123}"

COMPOSE_FILES="-f script/docker/docker-compose.yml \
               -f script/docker/docker-compose.health.yml \
               -f script/docker/docker-compose.local.yml \
               -f script/docker/docker-compose.mem.yml"

INFRA="mysql redis nacos"
# 库名 -> 脚本。顺序不重要，但必须与 datasource.yml 的声明一致
DB_MAP="ry-cloud:script/sql/ry-cloud.sql
ry-job:script/sql/ry-job.sql
ry-ai:script/sql/ry-ai.sql
ry-workflow:script/sql/ry-workflow.sql"

step() { printf '\n\033[1m▶ %s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
skip() { printf '  \033[90m·\033[0m %s（已存在，跳过）\n' "$1"; }
die()  { printf '  \033[31m✗ %s\033[0m\n' "$1"; exit 1; }

# ── 0. 前置检查 ─────────────────────────────────────────────────────
step "0. 前置检查"

docker info >/dev/null 2>&1 || die "连不上 Docker 守护进程，请先启动 Docker Desktop"

if [ ! -f script/docker/.env ]; then
  die "缺少 script/docker/.env（由 bootstrap-data.sh 生成）。
       请先执行：bash script/docker/bootstrap-data.sh"
fi
ok "Docker 可用，script/docker/.env 存在"

myq() { docker exec "$MYSQL_C" mysql -u"$DB_USER" -p"$DB_PASS" \
        --default-character-set=utf8mb4 -N -B -e "$1" 2>/dev/null; }

# ── 1. 起基础设施 ───────────────────────────────────────────────────
step "1. 起基础设施（mysql redis nacos）"
docker compose $COMPOSE_FILES up -d $INFRA 2>&1 | grep -E "Started|Running" | tail -3

printf '  等待就绪'
for i in $(seq 1 60); do
  hm=$(docker inspect -f '{{.State.Health.Status}}' "$MYSQL_C" 2>/dev/null)
  hn=$(docker inspect -f '{{.State.Health.Status}}' "$NACOS_C" 2>/dev/null)
  [ "$hm" = "healthy" ] && [ "$hn" = "healthy" ] && break
  printf '.'; sleep 3
done
echo
[ "$(docker inspect -f '{{.State.Health.Status}}' "$MYSQL_C" 2>/dev/null)" = "healthy" ] \
  || die "mysql 未能进入 healthy"
[ "$(docker inspect -f '{{.State.Health.Status}}' "$NACOS_C" 2>/dev/null)" = "healthy" ] \
  || die "nacos 未能进入 healthy"
ok "基础设施就绪"

# ── 2. 建库 ─────────────────────────────────────────────────────────
step "2. 创建业务库（4 个）"
for pair in $DB_MAP; do
  db="${pair%%:*}"
  docker exec "$MYSQL_C" mysql -u"$DB_USER" -p"$DB_PASS" \
    -e "CREATE DATABASE IF NOT EXISTS \`$db\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;" 2>/dev/null
  ok "$db"
done

# ── 3. 导入表结构 ───────────────────────────────────────────────────
step "3. 导入表结构（表数 > 0 则跳过）"
for pair in $DB_MAP; do
  db="${pair%%:*}"
  sql="${pair##*:}"
  n=$(myq "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$db';" | tr -d '\r')
  if [ "${n:-0}" -gt 0 ]; then
    skip "$db（已有 $n 张表）"
  else
    docker exec -i "$MYSQL_C" mysql -u"$DB_USER" -p"$DB_PASS" \
      --default-character-set=utf8mb4 "$db" < "$sql" 2>/dev/null
    n=$(myq "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$db';" | tr -d '\r')
    [ "${n:-0}" -gt 0 ] && ok "$db：导入 ${n} 张表" || die "$db 导入失败"
  fi
done

# ── 4. Nacos 管理员 ─────────────────────────────────────────────────
step "4. Nacos 管理员（一次性 bootstrap）"
login_resp=$(docker exec "$NACOS_C" curl -s -X POST "$NACOS_API/nacos/v3/auth/user/login" \
             -d "username=$NACOS_USER&password=$NACOS_PASS")
if printf '%s' "$login_resp" | grep -q '"accessToken"'; then
  skip "管理员 $NACOS_USER 已存在"
else
  printf '  未检测到管理员，执行一次性 bootstrap（密码：%s）… ' "$NACOS_PASS"
  r=$(docker exec "$NACOS_C" curl -s -X POST "$NACOS_API/nacos/v3/auth/user/admin" \
      -d "password=$NACOS_PASS")
  if printf '%s' "$r" | grep -q '"code":0'; then
    echo "成功"
    ok "管理员已创建：$NACOS_USER / $NACOS_PASS"
  else
    echo "失败"
    die "bootstrap 失败：$r"
  fi
fi

# ── 5. 导入 Nacos 配置 ──────────────────────────────────────────────
step "5. 导入 Nacos 配置"
./script/nacos-config-import.sh 2>&1 | tail -4

# ── 6. 可选：起最小集 ───────────────────────────────────────────────
if [ "${1:-}" = "--with-stack" ]; then
  step "6. 起最小集（gateway auth system）"
  ./script/stack.sh minimal up
else
  step "6. 起服务（跳过）"
  echo "  如需一并起服务：./script/bootstrap.sh --with-stack"
  echo "  或手动选择档位：./script/stack.sh {minimal|full} up"
fi

printf '\n\033[1m环境重建完成。\033[0m\n'
echo "  验收：./script/stack.sh minimal verify"
