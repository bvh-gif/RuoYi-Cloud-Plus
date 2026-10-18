#!/usr/bin/env bash
# 统一堆栈入口：按场景切换档位
#
# 环境：Git Bash / WSL / 任意能连 desktop-linux 的 docker CLI
#
# ── 三档的定位 ──────────────────────────────────────────────────────
#
#   minimal     常驻 3 个核心服务，~4.4GB
#               日常开发、改代码后联调。覆盖完整链路：
#               gateway → Nacos → auth/system → MySQL/Redis
#
#   verify-all  滚动验证 11 个模块，峰值 ~2.8GB（推荐）
#               同一时刻只多起一个模块，验完立刻停。
#               想验证「每个模块的代码都能起来并注册」，这是最省的方式。
#
#   full        11 个常驻，~12GB
#               正常使用。Docker 上限需 ≥ 16GB，建议调到 24GB。
#
# ── 为什么 verify-all 要滚动 ────────────────────────────────────────
# 内存成本取决于「同时有多少个 JVM 在跑」，不是「一共验证几个」。
# 11 个 JVM 同时跑 ≈ 7.7GB（堆 512m 时）；一次只跑 1 个 ≈ 堆 448m + 基础设施 1.6GB ≈ 2.8GB。
# 代价是串行耗时（每个约 1 分钟），但省掉一半以上的峰值内存。
#
# ── 用法 ────────────────────────────────────────────────────────────
#   ./script/stack.sh minimal    up|down|status|verify|mem
#   ./script/stack.sh full       up|down|status|verify|mem
#   ./script/stack.sh verify-all [batch]     # 默认滚动；加 batch 则一次性全起
#
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

COMPOSE_DIR="script/docker"
COMPOSE_FILES="-f ${COMPOSE_DIR}/docker-compose.yml \
               -f ${COMPOSE_DIR}/docker-compose.health.yml \
               -f ${COMPOSE_DIR}/docker-compose.local.yml \
               -f ${COMPOSE_DIR}/docker-compose.mem.yml"

INFRA="mysql redis nacos"
CORE="ruoyi-gateway ruoyi-auth ruoyi-system"
EXTRA="ruoyi-gen ruoyi-job ruoyi-resource ruoyi-workflow ruoyi-ai \
ruoyi-monitor ruoyi-snailjob-server ruoyi-snailai-server"
# 「模块:前置依赖」——依赖不在的话模块起不来（job 要 snailjob-server，ai 要 snailai-server）
EXTRA_WITH_DEPS="ruoyi-gen: ruoyi-job:ruoyi-snailjob-server \
ruoyi-resource: ruoyi-workflow: ruoyi-ai:ruoyi-snailai-server \
ruoyi-monitor: ruoyi-snailjob-server: ruoyi-snailai-server:"

dc() { docker compose $COMPOSE_FILES "$@"; }

# 每个模块验证时单独用的堆（滚动模式下可压得更低，因为同时只有一个）
DEFAULT_XMX=768m
DEFAULT_XMX_HEAVY=1g

set_heap() {
  export RUOYI_JVM_XMX="$1"
  export RUOYI_JVM_XMX_HEAVY="$2"
}

nacos_token() {
  docker exec nacos curl -s -X POST "http://127.0.0.1:8848/nacos/v3/auth/user/login" \
    -d "username=nacos&password=ruoyi123" \
    | sed -n 's/.*"accessToken":"\([^"]*\)".*/\1/p'
}

# 查某服务是否在 Nacos 中已注册且健康
registered() {
  local svc="$1" token="$2" r
  r=$(docker exec nacos curl -s -G "http://127.0.0.1:8848/nacos/v3/admin/ns/instance/list" \
      --data-urlencode "accessToken=$token" \
      --data-urlencode "serviceName=$svc" \
      --data-urlencode "groupName=DEFAULT_GROUP")
  printf '%s' "$r" | grep -q '"healthy":true'
}

show_mem() {
  echo "── 内存占用 ──"
  local total=0
  for c in $INFRA $CORE; do
    m=$(docker stats --no-stream --format "{{.MemUsage}}" "$c" 2>/dev/null | cut -d'/' -f1 | xargs)
    printf '  %-24s %s\n' "$c" "${m:-（已停止）}"
  done
}

profile_up() {
  local profile="$1"
  case "$profile" in
    minimal) set_heap 512m 640m; BUSINESS="$CORE" ;;
    full)    set_heap $DEFAULT_XMX $DEFAULT_XMX_HEAVY; BUSINESS="$CORE $EXTRA" ;;
  esac
  echo "── 档位 $profile：堆上限 ${RUOYI_JVM_XMX} / ${RUOYI_JVM_XMX_HEAVY} ──"
  dc up -d $INFRA 2>&1 | grep -E "Started|Running" | tail -3
  # 逐个起，避免同时创建导致内存尖峰
  for s in $BUSINESS; do
    dc up -d "$s" 2>&1 | grep -E "Started|Recreated" | tail -1
    sleep 8
  done
  echo
  echo "等待 60 秒完成启动与注册…"
  sleep 60
  case "$profile" in
    minimal) RUOYI_VERIFY_SERVICES="$CORE" ./script/verify-stack.sh ;;
    full)    ./script/verify-stack.sh ;;
  esac
}

profile_down() {
  docker stop $CORE 2>/dev/null | sed 's/^/  停 /'
  docker stop ruoyi-gen ruoyi-job ruoyi-resource ruoyi-workflow ruoyi-ai ruoyi-monitor \
             ruoyi-snailjob-server ruoyi-snailai-server 2>/dev/null | sed 's/^/  停 /'
  [ "${1:-}" = "all" ] && docker stop $INFRA 2>/dev/null | sed 's/^/  停 /'
  echo "完成"
}

# ── 滚动验证：一次只起一个，验完就停 ───────────────────────────────
verify_all_rolling() {
  set_heap 448m 640m
  local token pass=0 fail=0
  token=$(nacos_token)

  echo "── 滚动验证 11 个模块（堆上限 ${RUOYI_JVM_XMX} / ${RUOYI_JVM_XMX_HEAVY}）──"
  echo "   策略：一次只多起 1 个，确认注册后立即停止，峰值约 2.8GB"
  echo

  # 核心 3 个先常驻，它们是被依赖方
  dc up -d $INFRA 2>&1 | grep -cE "Started|Running" >/dev/null
  for s in $CORE; do dc up -d "$s" 2>&1 | grep -E "Started" | tail -1; done
  sleep 55

  for entry in $EXTRA_WITH_DEPS; do
    svc="${entry%%:*}"
    dep="${entry##*:}"
    [ "$dep" = "$entry" ] && dep=""
    [ -n "$dep" ] && dc up -d "$dep" 2>&1 | grep -E "Started" | tail -1
    dc up -d "$svc" 2>&1 | grep -E "Started|Recreated" | tail -1

    # 轮询最多 90 秒等注册
    ok=0
    for i in $(seq 1 18); do
      sleep 5
      if registered "$svc" "$token"; then ok=1; break; fi
    done
    if [ "$ok" = "1" ]; then
      printf '  \033[32mPASS\033[0m %-24s 已注册并健康\n' "$svc"
      pass=$((pass + 1))
    else
      printf '  \033[31mFAIL\033[0m %-24s 90 秒内未注册\n' "$svc"
      fail=$((fail + 1))
    fi

    docker stop "$svc" >/dev/null 2>&1
    [ -n "$dep" ] && docker stop "$dep" >/dev/null 2>&1
    sleep 3
  done

  echo
  echo "── 汇总：${pass} 个 PASS，${fail} 个 FAIL（核心 3 个已保留运行）──"
  [ "$fail" -gt 0 ] && exit 1
  exit 0
}

# ── 批量验证：一次性起全部，验完停掉非核心 ─────────────────────────
verify_all_batch() {
  set_heap 512m 640m
  echo "── 批量验证：一次性起 11 个（堆 ${RUOYI_JVM_XMX} / ${RUOYI_JVM_XMX_HEAVY}）──"
  echo "   峰值约 9GB，验完自动回收到最小集"
  dc up -d $INFRA 2>&1 | grep -cE "Started|Running" >/dev/null
  dc up -d $CORE $EXTRA 2>&1 | grep -E "Started" | wc -l | sed 's/^/  已启动 /'
  sleep 90
  ./script/verify-stack.sh
  echo
  echo "── 回收：停掉 8 个非核心，回落到最小集 ──"
  docker stop ruoyi-gen ruoyi-job ruoyi-resource ruoyi-workflow ruoyi-ai \
              ruoyi-monitor ruoyi-snailjob-server ruoyi-snailai-server 2>/dev/null \
    | sed 's/^/  停 /'
}

PROFILE="${1:-}"
ACTION="${2:-}"

case "$PROFILE" in
  minimal|full)
    case "$ACTION" in
      up)     profile_up "$PROFILE" ;;
      down)   profile_down "$3" ;;
      status) docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "NAMES|ruoyi-|nacos|mysql|redis" | grep -viE "3\.8\.5"; show_mem ;;
      verify) [ "$PROFILE" = minimal ] && RUOYI_VERIFY_SERVICES="$CORE" exec ./script/verify-stack.sh || exec ./script/verify-stack.sh ;;
      mem)    show_mem ;;
      *)      echo "用法：$0 {minimal|full} {up|down [all]|status|verify|mem}" ; exit 1 ;;
    esac
    ;;
  verify-all)
    [ "$ACTION" = "batch" ] && verify_all_batch || verify_all_rolling
    ;;
  *)
    cat <<'EOF'
用法：
  ./script/stack.sh minimal    up|down|status|verify|mem     # 常驻 3 个核心，~4.4GB
  ./script/stack.sh full       up|down|status|verify|mem     # 常驻 11 个，~12GB
  ./script/stack.sh verify-all [batch]                       # 滚动验证 11 个，峰值 ~2.8GB

档位说明：
  minimal     日常开发联调。保留 gateway/auth/system，链路完整。
  verify-all  验证「每个模块代码都能起来并注册」。滚动 = 一次只起一个，验完就停。
  full        正常使用。需先把 Docker 内存上限调至 ≥16GB（建议 24GB）。
EOF
    exit 1
    ;;
esac
