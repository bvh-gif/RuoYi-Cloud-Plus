#!/usr/bin/env bash
# 把 script/config/nacos/ 下的配置导入 Nacos 3.x
#
# 环境：Git Bash / WSL / PowerShell(bash)。靠 docker exec 在 nacos 容器内发请求，
# 这样绕开 host 网络下「宿主机连不到 8848」的问题。
#
# 用法：
#   ./script/nacos-config-import.sh            # 导入
#   ./script/nacos-config-import.sh --check    # 只列出 Nacos 里已有的 dataId
#
# ── 为什么不用 v2 的写法 ────────────────────────────────────────────
# Nacos 3.2.3 已彻底移除 /nacos/v1/cs/configs（GET 与 POST 都是 404）。
# 必须用 v3 admin API，且这些细节与 v2 不同：
#   * 鉴权：query 参数 accessToken=<token>（不是 header）
#   * 分组参数名是 groupName，不是 group
#   * type 需显式给（yaml / properties）
#
# ── 关于数据源密码 ──────────────────────────────────────────────────
# 上游 datasource.yml 写的是 password=password，但本仓库 compose 里
# MySQL root 是 ruoyi123（上游自身不一致）。这里只在「写入 Nacos 时」替换，
# 不改动仓库里的文件——清库重建后 compose 仍是 ruoyi123，配置依旧有效。
#
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

NACOS_CONTAINER="${NACOS_CONTAINER:-nacos}"
NACOS_API="${NACOS_API:-http://127.0.0.1:8848}"
NACOS_USER="${NACOS_USER:-nacos}"
NACOS_PASS="${NACOS_PASS:-ruoyi123}"
CONFIG_DIR="${CONFIG_DIR:-script/config/nacos}"
DB_PASSWORD="${DB_PASSWORD:-ruoyi123}"

CONFIG_TYPE_DEFAULT="yaml"

# seata 约定：dataId=seata-server.properties，group=SEATA_GROUP
# （seata 客户端默认就是这两个值，写错会导致 seata 拉不到配置）
SEATA_DATA_ID="seata-server.properties"
SEATA_GROUP="SEATA_GROUP"

MODE="${1:-import}"

# ── 登录 ────────────────────────────────────────────────────────────
login() {
  docker exec "$NACOS_CONTAINER" curl -s -X POST "$NACOS_API/nacos/v3/auth/user/login" \
    -d "username=$NACOS_USER&password=$NACOS_PASS"
}

TOKEN_JSON="$(login)"
TOKEN="$(printf '%s' "$TOKEN_JSON" | sed -n 's/.*"accessToken":"\([^"]*\)".*/\1/p')"

if [ -z "$TOKEN" ]; then
  echo "登录失败，响应：$TOKEN_JSON" >&2
  echo "提示：若从未初始化过管理员，先执行一次（一次性、不可逆）：" >&2
  echo "  docker exec $NACOS_CONTAINER curl -X POST '$NACOS_API/nacos/v3/auth/user/admin' -d 'password=<自定义>'" >&2
  exit 1
fi

# ── 仅列出 ──────────────────────────────────────────────────────────
if [ "$MODE" = "--check" ]; then
  echo "=== Nacos 中已有的配置 ==="
  docker exec "$NACOS_CONTAINER" curl -s -G "$NACOS_API/nacos/v3/admin/cs/config/list" \
    --data-urlencode "accessToken=$TOKEN" \
    --data-urlencode "groupName=" \
    --data-urlencode "pageNo=1" \
    --data-urlencode "pageSize=200"
  echo
  exit 0
fi

# ── 导入 ────────────────────────────────────────────────────────────
publish() {
  local data_id="$1" group="$2" type="$3" src="$4"
  local resp
  resp="$(docker exec -i "$NACOS_CONTAINER" curl -s -X POST \
    "$NACOS_API/nacos/v3/admin/cs/config?accessToken=$TOKEN" \
    --data-urlencode "dataId=$data_id" \
    --data-urlencode "groupName=$group" \
    --data-urlencode "type=$type" \
    --data-urlencode "content@-" < "$src")"
  if printf '%s' "$resp" | grep -q '"code":0'; then
    printf 'OK    %-32s [%s]\n' "$data_id" "$group"
  else
    printf 'FAIL  %-32s [%s] -> %s\n' "$data_id" "$group" "$resp"
    return 1
  fi
}

fail=0

for f in "$CONFIG_DIR"/*.yml; do
  [ -e "$f" ] || continue
  data_id="$(basename "$f")"

  if [ "$data_id" = "datasource.yml" ]; then
    # 只在写入时替换密码，不动仓库文件
    tmp="$(mktemp)"
    sed "s/^\(\s*\)password:[[:space:]]*password[[:space:]]*$/\1password: $DB_PASSWORD/" "$f" > "$tmp"
    publish "$data_id" "DEFAULT_GROUP" "yaml" "$tmp" || fail=$((fail + 1))
    rm -f "$tmp"
  else
    publish "$data_id" "DEFAULT_GROUP" "yaml" "$f" || fail=$((fail + 1))
  fi
done

if [ -f "$CONFIG_DIR/$SEATA_DATA_ID" ]; then
  publish "$SEATA_DATA_ID" "$SEATA_GROUP" "properties" "$CONFIG_DIR/$SEATA_DATA_ID" || fail=$((fail + 1))
else
  echo "SKIP  $SEATA_DATA_ID（文件不存在）"
fi

echo "----------------------------------------"
echo "导入完成，失败数=$fail"
exit "$fail"
