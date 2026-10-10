#!/usr/bin/env bash
# =============================================================================
# RuoYi-Cloud-Plus —— 本地依赖就绪检查（readiness）
#
# 与设计对应（团队规范 §7）：
#   - 进程存在 / 容器运行 ≠ 可用。这里每项检查都对应该服务真实的业务能力：
#       MySQL  → 用容器自身凭据完成认证 + 执行轻量查询
#       Redis  → 处理 requirepass，执行真实 PING 并校验 PONG
#       Nacos  → 控制台可达 + 命名服务 API 可用 + （可选）指定服务有实例
#   - 有限轮询，不是固定 sleep；超时返回非零退出码
#   - 失败输出包含：检查项、失败原因、下一步排查提示
#
# 用法：
#   bash script/docker/readiness.sh                    # 检查一次
#   bash script/docker/readiness.sh --wait 120         # 最多等待 120 秒
#   bash script/docker/readiness.sh --expect ruoyi-system,ruoyi-auth
#                                                      # 额外要求这些服务已注册实例
#
# 退出码：
#   0  全部就绪
#   1  参数错误
#   2  Docker / Compose 不可用
#   3  等待超时
#   4  检查失败（依赖未就绪）
#
# 环境变量可覆盖：
#   MYSQL_CT / REDIS_CT / NACOS_CT   容器名（默认 mysql / redis / nacos）
#   NACOS_HOST                       Nacos HTTP 地址（默认 127.0.0.1:8848）
#   NACOS_AUTH                       "user:pass"，Nacos 开启鉴权时必填
#   WAIT / INTERVAL                  等待秒数 / 轮询间隔
# =============================================================================
set -uo pipefail

MYSQL_CT="${MYSQL_CT:-mysql}"
REDIS_CT="${REDIS_CT:-redis}"
NACOS_CT="${NACOS_CT:-nacos}"
NACOS_HOST="${NACOS_HOST:-127.0.0.1:8848}"
WAIT="${WAIT:-0}"
INTERVAL="${INTERVAL:-3}"
EXPECT="${EXPECT:-}"

EXIT_USAGE=1
EXIT_DOCKER=2
EXIT_TIMEOUT=3
EXIT_FAILED=4

usage() {
  sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
}

warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }
info() { printf '%s\n' "$*"; }

now() { date +%s; }

# ---------------------------------------------------------------- Docker ----
docker_available() {
  command -v docker >/dev/null 2>&1 || return 1
  docker info >/dev/null 2>&1 || return 1
}

container_running() {
  local name="$1"
  [ -n "$(docker ps --filter "name=^${name}\$" --filter "status=running" -q 2>/dev/null)" ]
}

container_exists() {
  [ -n "$(docker ps -a --filter "name=^${1}\$" -q 2>/dev/null)" ]
}

# ----------------------------------------------------------------- MySQL ----
probe_mysql() {
  container_running "$MYSQL_CT" || { echo "容器未运行"; return 1; }
  local out
  out="$(docker exec "$MYSQL_CT" sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N -B -e "SELECT 1"' 2>&1)"
  # 注意：mysql 客户端会把 "Using a password" 警告打到 stderr，故按行精确匹配结果，
  # 不能先把整段空白删掉再比对。行尾 \r 也要处理（Windows 挂载配置/输出常见）。
  if printf '%s\n' "$out" | tr -d '\r' | grep -qx '1'; then
    return 0
  fi
  # 屏蔽密码回显类噪声，只保留有诊断价值的一行
  echo "认证或查询失败: $(printf '%s' "$out" | grep -v 'Using a password' | head -1)"
  return 1
}

# ----------------------------------------------------------------- Redis ----
# Redis 可能启用了 requirepass（本项目就是），裸 PING 会返回 NOAUTH。
# 这里从容器挂载的 redis.conf 里读出口令，不打印口令本身。
probe_redis() {
  container_running "$REDIS_CT" || { echo "容器未运行"; return 1; }
  local out
  out="$(docker exec -i "$REDIS_CT" sh -s <<'EOS' 2>&1
conf=""
for f in /redis/config/redis.conf /usr/local/etc/redis/redis.conf /etc/redis/redis.conf; do
  [ -f "$f" ] && { conf="$f"; break; }
done
pass=""
if [ -n "$conf" ]; then
  # 必须去掉行尾 \\r：挂载的 redis.conf 若为 CRLF，$2 会带上回车导致 WRONGPASS
  pass=$(tr -d '\r' < "$conf" | awk '$1=="requirepass"{print $2; exit}')
fi
if [ -n "$pass" ]; then
  exec redis-cli -a "$pass" --no-auth-warning ping
else
  exec redis-cli ping
fi
EOS
)"
  if printf '%s' "$out" | grep -qx 'PONG'; then
    return 0
  fi
  echo "PING 未返回 PONG: $(printf '%s' "$out" | tr '\n' ' ' | head -c 160)"
  return 1
}

# ----------------------------------------------------------------- Nacos ----
nacos_curl() {
  local path="$1" out
  if [ -n "${NACOS_AUTH:-}" ]; then
    out="$(curl -fsS -u "$NACOS_AUTH" -m 6 "http://${NACOS_HOST}${path}" 2>&1)"
  else
    out="$(curl -fsS -m 6 "http://${NACOS_HOST}${path}" 2>&1)"
  fi
  printf '%s' "$out"
}

probe_nacos() {
  container_running "$NACOS_CT" || { echo "容器未运行"; return 1; }

  local body
  body="$(nacos_curl "/nacos/index.html")"
  if [ -z "$body" ]; then
    echo "控制台不可达 (http://${NACOS_HOST}/nacos/index.html)"
    return 1
  fi

  # 真正的就绪判定：命名服务 API 能返回结构化结果（说明注册中心可用）
  body="$(nacos_curl "/nacos/v1/ns/instance/list?serviceName=probe-$(now)")"
  if [ -z "$body" ]; then
    echo "命名服务 API 不可达 (/nacos/v1/ns/instance/list)"
    return 1
  fi
  # Nacos 对不存在的服务返回 {"name":"GROUP@@svc","hosts":[],"cacheMillis":...}，
  # 不会出现 serviceName 字段，所以用结构化字段是否存在判断 API 真的在工作。
  if ! printf '%s' "$body" | grep -q '"cacheMillis"'; then
    echo "命名服务 API 返回异常: $(printf '%s' "$body" | head -c 120)"
    return 1
  fi
  return 0
}

probe_registered() {
  local name="$1" body count
  body="$(nacos_curl "/nacos/v1/ns/instance/list?serviceName=${name}")"
  if [ -z "$body" ]; then
    echo "查询失败"
    return 1
  fi
  count="$(printf '%s' "$body" | grep -o '"ip":' | wc -l | tr -d '[:space:]')"
  if [ "${count:-0}" -lt 1 ]; then
    echo "已注册实例数 0"
    return 1
  fi
  echo "已注册实例数 ${count}"
  return 0
}

# --------------------------------------------------------------- 汇总执行 ----
declare -a SUMMARY=()

run_checks() {
  local rc=0
  local msg

  # MySQL
  if msg="$(probe_mysql)"; then
    SUMMARY+=("OK      mysql        认证成功，SELECT 1 通过")
  else
    SUMMARY+=("FAIL    mysql        ${msg}")
    rc=1
  fi

  # Redis
  if msg="$(probe_redis)"; then
    SUMMARY+=("OK      redis        PING 返回 PONG")
  else
    SUMMARY+=("FAIL    redis        ${msg}")
    rc=1
  fi

  # Nacos
  if msg="$(probe_nacos)"; then
    SUMMARY+=("OK      nacos        控制台与命名服务 API 均可用")
  else
    SUMMARY+=("FAIL    nacos        ${msg}")
    rc=1
  fi

  # 可选：要求指定服务已注册（服务发现真正生效的判据）
  if [ -n "$EXPECT" ]; then
    local oldifs="$IFS"
    IFS=','
    for svc in $EXPECT; do
      [ -n "$svc" ] || continue
      if msg="$(probe_registered "$svc")"; then
        SUMMARY+=("OK      ${svc}   ${msg}")
      else
        SUMMARY+=("FAIL    ${svc}   ${msg}")
        rc=1
      fi
    done
    IFS="$oldifs"
  fi

  return $rc
}

print_summary() {
  info ""
  info "================= readiness 结果 ================="
  local line
  for line in "${SUMMARY[@]}"; do
    info "$line"
  done
  info "=================================================="
}

main() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --wait)     WAIT="${2:-}"; shift 2 ;;
      --interval) INTERVAL="${2:-}"; shift 2 ;;
      --expect)   EXPECT="${2:-}"; shift 2 ;;
      -h|--help)  usage; exit 0 ;;
      *)          warn "未知参数: $1"; usage; exit "$EXIT_USAGE" ;;
    esac
  done

  case "${WAIT}" in ''|*[!0-9]*) warn "--wait 必须是整数秒"; exit "$EXIT_USAGE";; esac
  case "${INTERVAL}" in ''|*[!0-9]*|0*) warn "--interval 必须是正整数"; exit "$EXIT_USAGE";; esac

  docker_available || {
    warn "Docker daemon 不可达。请确认 Docker Desktop 已启动，或执行 docker info 查看具体错误。"
    exit "$EXIT_DOCKER"
  }

  for c in "$MYSQL_CT" "$REDIS_CT" "$NACOS_CT"; do
    container_exists "$c" || {
      warn "容器不存在: $c。当前运行中的容器："
      docker ps --format '  {{.Names}} ({{.Image}})' >&2
      exit "$EXIT_FAILED"
    }
  done

  if run_checks; then
    print_summary
    info "全部就绪。"
    exit 0
  fi

  if [ "${WAIT}" -gt 0 ]; then
    local deadline=$(( $(now) + WAIT ))
    info ""
    info "依赖未完全就绪，进入轮询等待（上限 ${WAIT}s，间隔 ${INTERVAL}s）..."
    while [ "$(now)" -lt "$deadline" ]; do
      sleep "$INTERVAL"
      SUMMARY=()
      if run_checks; then
        print_summary
        info "等待后全部就绪（耗时约 $(( WAIT - (deadline - $(now)) ))s）。"
        exit 0
      fi
    done
    print_summary
    warn "等待 ${WAIT}s 后仍未就绪，超时退出。"
    warn "下一步排查：docker logs ${NACOS_CT} --tail 100 ; docker inspect ${MYSQL_CT} --format '{{.State.Health.Status}}'"
    exit "$EXIT_TIMEOUT"
  fi

  print_summary
  warn "依赖未就绪。建议：docker compose ps 查看状态，或用 --wait 120 等待启动完成。"
  exit "$EXIT_FAILED"
}

main "$@"
