#!/usr/bin/env bash
# 一键验收：镜像 / 数据库 / Nacos 配置 / 服务注册 / 端到端调用
#
# 环境：Git Bash / WSL / 任意能连 desktop-linux 的 docker CLI
# 用法：
#   ./script/verify-stack.sh
#
# 设计说明：
#   * 所有对 Nacos 的请求都在 nacos 容器内发起（docker exec），
#     这样绕开 host 网络下「宿主机连不到 8848」的限制。
#   * 逐项打印 PASS / FAIL，最后给汇总。退出码 = FAIL 项数。
#
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

NACOS_CONTAINER="${NACOS_CONTAINER:-nacos}"
MYSQL_CONTAINER="${MYSQL_CONTAINER:-mysql}"
NACOS_API="${NACOS_API:-http://127.0.0.1:8848}"
NACOS_USER="${NACOS_USER:-nacos}"
NACOS_PASS="${NACOS_PASS:-ruoyi123}"
DB_USER="${DB_USER:-root}"
DB_PASS="${DB_PASS:-ruoyi123}"

# 期望值（改环境就改这里）
EXPECT_IMAGES=11
EXPECT_DBS="ry-cloud ry-job ry-ai ry-workflow"
EXPECT_CONFIGS=14
# 可用环境变量覆盖，做低资源验证时只需验最小集：
#   RUOYI_VERIFY_SERVICES="ruoyi-gateway ruoyi-auth ruoyi-system" ./script/verify-stack.sh
EXPECT_SERVICES="${RUOYI_VERIFY_SERVICES:-ruoyi-gateway ruoyi-auth ruoyi-system \
ruoyi-gen ruoyi-job ruoyi-resource ruoyi-workflow ruoyi-ai ruoyi-monitor \
ruoyi-snailjob-server ruoyi-snailai-server}"

PASS=0
FAIL=0
pass() { printf '  \033[32mPASS\033[0m %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL + 1)); }

echo "════════════════════════════════════════════════"
echo " 1. 业务镜像"
echo "════════════════════════════════════════════════"
n=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep -c '^ruoyi/ruoyi-.*:6\.0\.0')
if [ "$n" -eq "$EXPECT_IMAGES" ]; then
  pass "业务镜像 $n / $EXPECT_IMAGES"
  docker images --format '{{.Repository}}:{{.Tag}}  {{.Size}}' | grep '^ruoyi/ruoyi-' | sed 's/^/       /'
else
  fail "业务镜像 $n / $EXPECT_IMAGES（缺 $((EXPECT_IMAGES - n)) 个）"
fi

echo
echo "════════════════════════════════════════════════"
echo " 2. 数据库表结构"
echo "════════════════════════════════════════════════"
for db in $EXPECT_DBS; do
  t=$(docker exec "$MYSQL_CONTAINER" mysql -u"$DB_USER" -p"$DB_PASS" --default-character-set=utf8mb4 -N \
      -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$db';" 2>/dev/null | tr -d '\r')
  if [ -n "$t" ] && [ "$t" -gt 0 ]; then
    pass "$db : $t 张表"
  else
    fail "$db : 表数 $t（无表或库不存在）"
  fi
done
# 顺便验一下中文没乱码（客户端默认 latin1 会显示成 ?????，必须显式指定 utf8mb4）
nick=$(docker exec "$MYSQL_CONTAINER" mysql -u"$DB_USER" -p"$DB_PASS" --default-character-set=utf8mb4 -N \
       -e "SELECT nick_name FROM \`ry-cloud\`.sys_user WHERE user_name='admin';" 2>/dev/null | tr -d '\r')
if [ "$nick" = "疯狂的狮子Li" ]; then
  pass "中文数据正常（admin 昵称 = $nick）"
else
  fail "中文数据异常：读到 '$nick'（预期 '疯狂的狮子Li'）"
fi

echo
echo "════════════════════════════════════════════════"
echo " 3. Nacos 配置"
echo "════════════════════════════════════════════════"
TOKEN=$(docker exec "$NACOS_CONTAINER" curl -s -X POST "$NACOS_API/nacos/v3/auth/user/login" \
        -d "username=$NACOS_USER&password=$NACOS_PASS" \
        | sed -n 's/.*"accessToken":"\([^"]*\)".*/\1/p')
if [ -z "$TOKEN" ]; then
  fail "Nacos 登录失败（管理员未初始化或凭据错误）"
else
  pass "Nacos 登录成功（$NACOS_USER）"
  cnt=0
  for f in script/config/nacos/*.yml; do
    [ -e "$f" ] || continue
    id=$(basename "$f")
    r=$(docker exec "$NACOS_CONTAINER" curl -s -G "$NACOS_API/nacos/v3/admin/cs/config" \
        --data-urlencode "accessToken=$TOKEN" --data-urlencode "dataId=$id" \
        --data-urlencode "groupName=DEFAULT_GROUP")
    if printf '%s' "$r" | grep -q '"code":0'; then cnt=$((cnt + 1)); else fail "$id 缺失"; fi
  done
  r=$(docker exec "$NACOS_CONTAINER" curl -s -G "$NACOS_API/nacos/v3/admin/cs/config" \
      --data-urlencode "accessToken=$TOKEN" --data-urlencode "dataId=seata-server.properties" \
      --data-urlencode "groupName=SEATA_GROUP")
  printf '%s' "$r" | grep -q '"code":0' && cnt=$((cnt + 1)) || fail "seata-server.properties 缺失"
  if [ "$cnt" -eq "$EXPECT_CONFIGS" ]; then
    pass "配置齐全 $cnt / $EXPECT_CONFIGS"
  else
    fail "配置 $cnt / $EXPECT_CONFIGS"
  fi
fi

echo
echo "════════════════════════════════════════════════"
echo " 4. 服务注册"
echo "════════════════════════════════════════════════"
if [ -n "${TOKEN:-}" ]; then
  for s in $EXPECT_SERVICES; do
    r=$(docker exec "$NACOS_CONTAINER" curl -s -G "$NACOS_API/nacos/v3/admin/ns/instance/list" \
        --data-urlencode "accessToken=$TOKEN" --data-urlencode "serviceName=$s" \
        --data-urlencode "groupName=DEFAULT_GROUP")
    if printf '%s' "$r" | grep -q '"healthy":true'; then
      ip=$(printf '%s' "$r" | sed -n 's/.*"ip":"\([^"]*\)".*/\1/p' | head -1)
      port=$(printf '%s' "$r" | sed -n 's/.*"port":\([0-9]*\).*/\1/p' | head -1)
      pass "$s 已注册且健康  $ip:$port"
    else
      fail "$s 未注册或不健康"
    fi
  done
else
  fail "跳过（无 token）"
fi

echo
echo "════════════════════════════════════════════════"
echo " 5. 端到端调用（从容器内打网关）"
echo "════════════════════════════════════════════════"
# 注意：/code 的 HTTP 状态码恒为 200，但 body 里才是真实业务码
# （未带 token 时 body = {"code":401,"msg":"未能读取到有效 token"}）。
# 只查 HTTP 码会永远 PASS，必须同时校验响应体是结构化 JSON。
gw_body=$(docker exec "$NACOS_CONTAINER" curl -s --max-time 15 "http://127.0.0.1:8080/code")
gw_code=$(docker exec "$NACOS_CONTAINER" curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
          "http://127.0.0.1:8080/code")
if [ "$gw_code" = "200" ] && printf '%s' "$gw_body" | grep -q '"code"'; then
  pass "GET /code → HTTP 200 且返回结构化响应"
  printf '       响应：%s\n' "$(printf '%s' "$gw_body" | head -c 120)"
else
  fail "GET /code → HTTP $gw_code，响应：$(printf '%s' "$gw_body" | head -c 120)"
fi
# 这里故意只传 username/password：
# api-decrypt.enabled=true（上游默认）时，/auth/login 带 @ApiEncrypt，
# 明文请求体会被 CryptoFilter 丢弃，auth 拿到空 body → 返回
# {"code":500,"msg":"认证客户端id不能为空"}。
# 拿到这条响应 = 请求确实穿透到了 auth 的业务校验层，链路是通的。
# 想做真实登录需先关掉 api-decrypt 与验证码，并按协议加密请求体。
r=$(docker exec "$NACOS_CONTAINER" curl -s --max-time 15 -X POST "http://127.0.0.1:8080/auth/login" \
    -H "Content-Type: application/json" -d '{"username":"admin","password":"admin123"}')
if printf '%s' "$r" | grep -q '"code"'; then
  pass "POST /auth/login 收到业务响应（网关→auth 链路通）"
  printf '       响应：%s\n' "$(printf '%s' "$r" | head -c 160)"
else
  fail "POST /auth/login 无响应：$(printf '%s' "$r" | head -c 120)"
fi

echo
echo "════════════════════════════════════════════════"
if [ "$FAIL" -eq 0 ]; then
  printf ' 全部通过：%s 项 PASS，0 项 FAIL\n' "$PASS"
else
  printf ' 存在失败：%s 项 PASS，%s 项 FAIL\n' "$PASS" "$FAIL"
fi
echo "════════════════════════════════════════════════"
exit "$FAIL"
