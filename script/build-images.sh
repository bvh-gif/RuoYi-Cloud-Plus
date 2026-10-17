#!/usr/bin/env bash
# 批量构建业务镜像（Day 2）
# 环境：Git Bash / WSL，需在仓库根目录执行
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

TAG="${TAG:-6.0.0}"

# 模块目录 -> 镜像名（镜像名必须严格匹配 docker-compose.yml 中的 image:）
MODULES=(
  "ruoyi-auth:ruoyi/ruoyi-auth"
  "ruoyi-modules/ruoyi-system:ruoyi/ruoyi-system"
  "ruoyi-modules/ruoyi-gen:ruoyi/ruoyi-gen"
  "ruoyi-modules/ruoyi-job:ruoyi/ruoyi-job"
  "ruoyi-modules/ruoyi-resource:ruoyi/ruoyi-resource"
  "ruoyi-modules/ruoyi-workflow:ruoyi/ruoyi-workflow"
  "ruoyi-modules/ruoyi-ai:ruoyi/ruoyi-ai"
  "ruoyi-visual/ruoyi-monitor:ruoyi/ruoyi-monitor"
  "ruoyi-visual/ruoyi-snailjob-server:ruoyi/ruoyi-snailjob-server"
  "ruoyi-visual/ruoyi-snailai-server:ruoyi/ruoyi-snailai-server"
)

fail=0
for entry in "${MODULES[@]}"; do
  dir="${entry%%:*}"
  image="${entry##*:}"
  echo "=============================================================="
  echo "[$(date '+%H:%M:%S')] 构建 ${image}:${TAG}  <- ${dir}"
  echo "=============================================================="
  if docker build -t "${image}:${TAG}" "./${dir}"; then
    echo "[$(date '+%H:%M:%S')] OK   ${image}:${TAG}"
  else
    echo "[$(date '+%H:%M:%S')] FAIL ${image}:${TAG}"
    fail=$((fail + 1))
  fi
done

echo "=============================================================="
echo "[$(date '+%H:%M:%S')] 全部完成，失败数=${fail}"
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | grep '^ruoyi/ruoyi' | sort
exit ${fail}
