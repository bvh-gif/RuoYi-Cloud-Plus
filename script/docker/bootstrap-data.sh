#!/usr/bin/env bash
#
# 为容器准备「与启动上下文无关」的本地数据目录。
#
# ── 为什么需要这个脚本 ──────────────────────────────────────────────
# 上游 docker-compose.yml 里的数据卷用的是绝对路径 /docker/...，而它
# 在不同终端下会被 Docker Desktop 解析到完全不同的位置：
#
#   从 WSL Ubuntu 启动  → /docker = Ubuntu 发行版的 /docker（ext4，旧副本 B 的数据）
#   从 Git Bash 启动    → /docker = docker-desktop 虚拟机内的 /docker（空目录）
#
# 同一条 docker compose 命令、换个终端就换了数据库，且不报错。
# 本脚本 + docker-compose.local.yml 把数据卷改到 /mnt/d/... 形式，
# 两种终端下都会被 Docker Desktop 翻译成 D:\...，行为一致、Windows 下可见。
#
# 用法：
#   bash script/docker/bootstrap-data.sh          # 创建目录 + 生成 nacos 配置
#   bash script/docker/bootstrap-data.sh --check  # 只检查，不写入
#
set -euo pipefail

# 从脚本自身位置推导，而不是 pwd —— 这样从任何目录调用都得到相同结果
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"

# ── 按 shell 上下文选择「宿主机路径形态」 ───────────────────────────
# 同一个 Windows 目录，三种终端写法完全不同，写错就会静默建到别处：
#
#   WSL Ubuntu    /mnt/d/dev/project/...   Docker Desktop 原样接受
#   Git Bash      /d/dev/project/...       需转成 D:/dev/project/...
#   PowerShell    D:\dev\project\...       （本脚本不覆盖，仅供对照）
#
# ⚠ 最大的坑：不要以为 /mnt/d/... 在 Git Bash 里也指向 D 盘。
#   Git Bash 的 / 是 PortableGit 安装目录，/mnt/d/... 是它下面的普通子目录，
#   照抄会把数据建到 D:\...\PortableGit\mnt\d\... ，而且不报错。
#   这里因此按 uname 判定上下文，而不是无脑拼字符串。
UNAME_S="$(uname -s)"
case "${UNAME_S}" in
  Linux)                                   # ── WSL ──
    case "${SCRIPT_DIR}" in
      /mnt/?) SCRIPT_DIR_HOST="${SCRIPT_DIR}" ;;
      *) die "WSL 下期望脚本位于 /mnt/<盘符>/...，实际为：${SCRIPT_DIR}" ;;
    esac
    LAUNCH_CTX="WSL (${UNAME_S})"
    ;;
  MINGW*|MSYS*)                            # ── Git Bash ──
    case "${SCRIPT_DIR}" in
      /[a-zA-Z]/*)
        _body="${SCRIPT_DIR#/}"            # d/dev/project/...
        _drv="${_body%%/*}"                # d
        _rest="${_body#*/}"                # dev/project/...
        _drv="$(printf '%s' "${_drv}" | tr '[:lower:]' '[:upper:]')"
        SCRIPT_DIR_HOST="${_drv}:/${_rest}"   # D:/dev/project/...
        ;;
      *) die "Git Bash 下期望脚本位于 /<盘符>/...，实际为：${SCRIPT_DIR}" ;;
    esac
    LAUNCH_CTX="Git Bash (${UNAME_S})"
    ;;
  *)
    die "未识别的运行环境 uname -s=${UNAME_S}。请手动设置 RUOYI_DATA_ROOT 后重试。"
    ;;
esac
REPO_ROOT_HOST="$(dirname "$(dirname "${SCRIPT_DIR_HOST}")")"

DATA_ROOT="${RUOYI_DATA_ROOT:-${REPO_ROOT_HOST}/.local-data}"

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

log "启动上下文        : ${LAUNCH_CTX}"
log "仓库根（宿主机视角）: ${REPO_ROOT_HOST}"
log "数据根            : ${DATA_ROOT}"

# ── 1. 目录骨架 ────────────────────────────────────────────────────
DIRS="
${DATA_ROOT}/mysql/data
${DATA_ROOT}/mysql/conf
${DATA_ROOT}/redis/data
${DATA_ROOT}/redis/conf
${DATA_ROOT}/nacos/logs
${DATA_ROOT}/nacos/conf
"

if [ "${CHECK_ONLY}" -eq 1 ]; then
  log ""
  log "[--check] 目录状态："
  for d in ${DIRS}; do
    if [ -d "${d}" ]; then
      log "  OK      ${d}  ($(ls -1 "${d}" 2>/dev/null | wc -l) 个条目)"
    else
      log "  MISSING ${d}"
    fi
  done
else
  for d in ${DIRS}; do
    mkdir -p "${d}"
    log "  mkdir -p ${d}"
  done
fi

# ── 2. 生成启用 MySQL 的 nacos 配置 ─────────────────────────────────
# 上游 script/docker/nacos/conf/application.properties 里
# db.num / db.url.0 / db.user / db.password 四行全被注释掉了，
# 导致 Nacos 跑在内嵌 Derby 上：配置能写进去，重启就丢，且不报错。
# 这里生成一份「取消注释版」供容器挂载，上游文件保持不动。
SRC="${REPO_ROOT}/script/docker/nacos/conf/application.properties"
DST="${DATA_ROOT}/nacos/conf/application.properties"

[ -f "${SRC}" ] || die "找不到上游 nacos 配置: ${SRC}"

if [ "${CHECK_ONLY}" -eq 1 ]; then
  log ""
  if [ -f "${DST}" ]; then
    n="$(grep -cE '^db\.(num|url\.0|user|password)=' "${DST}" || true)"
    log "[--check] ${DST} 已存在，启用的 DB 配置行数 = ${n}（期望 4）"
  else
    log "[--check] ${DST} 尚未生成"
  fi
  exit 0
fi

cp "${SRC}" "${DST}"

# 只按行首前缀匹配，不锚定行尾 —— 上游文件是 CRLF，行尾有 \r
sed -i -E \
  -e 's/^#[[:space:]]*(db\.num=1)/\1/' \
  -e 's/^#[[:space:]]*(db\.url\.0=)/\1/' \
  -e 's/^#[[:space:]]*(db\.user=)/\1/' \
  -e 's/^#[[:space:]]*(db\.password=)/\1/' \
  "${DST}"

n="$(grep -cE '^db\.(num|url\.0|user|password)=' "${DST}" || true)"
[ "${n}" -eq 4 ] || die "生成失败：期望 4 行启用，实际 ${n} 行。请检查 ${DST}"

log ""
log "已生成 ${DST}"
log "启用的 DB 配置："
grep -E '^db\.(num|url\.0|user|password)=' "${DST}" \
  | sed -E 's/(password=).*/\1<redacted>/' \
  | sed 's/^/    /'

# ── 2.5 复制 redis.conf ────────────────────────────────────────────
# 容器启动命令是 redis-server /redis/config/redis.conf，
# 配置里 dir 指向 /redis/data，所以配置文件必须落在数据根下一起挂载。
SRC_REDIS_CONF="${REPO_ROOT}/script/docker/redis/conf/redis.conf"
DST_REDIS_CONF="${DATA_ROOT}/redis/conf/redis.conf"
[ -f "${SRC_REDIS_CONF}" ] || die "找不到上游 redis 配置: ${SRC_REDIS_CONF}"
cp "${SRC_REDIS_CONF}" "${DST_REDIS_CONF}"
log ""
log "已复制 ${SRC_REDIS_CONF}"
log "     → ${DST_REDIS_CONF}"

# ── 3. 生成 .env，供 compose 插值使用 ───────────────────────────────
# 为什么不把路径硬编码进 docker-compose.local.yml：
#   硬编码会把「这台机器的绝对路径」提交进仓库，仓库一挪就失效。
#   改由本脚本按当前位置生成 .env，compose 用 ${RUOYI_DATA_ROOT} 引用。
ENV_FILE="${SCRIPT_DIR}/.env"
if [ -f "${ENV_FILE}" ]; then
  cp "${ENV_FILE}" "${ENV_FILE}.bak"
  log ""
  log "已备份旧 .env → .env.bak"
fi
cat > "${ENV_FILE}" <<EOF
# 由 bootstrap-data.sh 自动生成，请勿手动编辑（重新运行脚本会覆盖）
RUOYI_DATA_ROOT=${DATA_ROOT}
EOF
log ""
log "已写入 ${ENV_FILE}"
log "  RUOYI_DATA_ROOT=${DATA_ROOT}"

log ""
log "完成。下一步："
log "  cd ${SCRIPT_DIR}"
log "  docker compose -f docker-compose.yml -f docker-compose.health.yml -f docker-compose.local.yml up -d mysql redis nacos"
