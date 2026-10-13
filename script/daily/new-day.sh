#!/usr/bin/env bash
#
# 生成当天（或指定日期）的工作结果记录文件。
#
# ── 解决什么问题 ────────────────────────────────────────────────────
# 每天手动复制模板、改文件名、改标题里的日期和星期，是一件机械但容易
# 出错的事——尤其星期几很容易填错。本脚本把这几步固化下来。
#
# ── 用法 ────────────────────────────────────────────────────────────
#   bash script/daily/new-day.sh              # 用今天
#   bash script/daily/new-day.sh 2026-10-14   # 指定日期
#
# ── 行为 ────────────────────────────────────────────────────────────
#   · 从 docs/daily/TEMPLATE.md 生成 docs/daily/YYYY-MM-DD.md
#   · 自动填入日期、星期、Day 编号与当天任务名
#   · 目标文件已存在时拒绝覆盖（避免误删当天记录）
#   · 日期不在排期表内（周末 / 已过）时仍生成，Day 信息留空待填
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"
DAILY_DIR="${REPO_ROOT}/docs/daily"
TEMPLATE="${DAILY_DIR}/TEMPLATE.md"

DATE="${1:-$(date +%F)}"

# ── 参数与前置校验 ──────────────────────────────────────────────────
if ! [[ "${DATE}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "错误：日期格式应为 YYYY-MM-DD，收到 '${DATE}'" >&2
  exit 1
fi

if [ ! -f "${TEMPLATE}" ]; then
  echo "错误：找不到模板文件 ${TEMPLATE}" >&2
  exit 1
fi

TARGET="${DAILY_DIR}/${DATE}.md"
if [ -f "${TARGET}" ]; then
  echo "已存在：${TARGET}"
  echo "为安全起见不覆盖。如需重建，请先手动删除该文件。" >&2
  exit 1
fi

if ! DOW_NUM="$(date -d "${DATE}" +%u 2>/dev/null)"; then
  echo "错误：无法解析日期 '${DATE}'（本脚本依赖 GNU date）" >&2
  exit 1
fi

case "${DOW_NUM}" in
  1) WEEKDAY="一" ;;
  2) WEEKDAY="二" ;;
  3) WEEKDAY="三" ;;
  4) WEEKDAY="四" ;;
  5) WEEKDAY="五" ;;
  6) WEEKDAY="六" ;;
  7) WEEKDAY="日" ;;
  *) WEEKDAY="?" ;;
esac

# ── 排期映射表 ──────────────────────────────────────────────────────
# 对应 docs/plan-wsl-docker_2026_10_13.md 第四章的 14 个工作日。
# 排期调整时，同步更新这里。
DAY_NUM="（非排期工作日）"
DAY_TASK="（手工填写）"

case "${DATE}" in
  2026-10-13) DAY_NUM="Day 0";  DAY_TASK="计划制定 + 环境准备" ;;
  2026-10-14) DAY_NUM="Day 1";  DAY_TASK="Maven 构建验证" ;;
  2026-10-15) DAY_NUM="Day 2";  DAY_TASK="构建 12 个业务镜像" ;;
  2026-10-16) DAY_NUM="Day 3";  DAY_TASK="Nacos 配置导入" ;;
  2026-10-19) DAY_NUM="Day 4";  DAY_TASK="host 下注册验证" ;;
  2026-10-20) DAY_NUM="Day 5";  DAY_TASK="bridge 网络迁移" ;;
  2026-10-21) DAY_NUM="Day 6";  DAY_TASK="前端构建与部署" ;;
  2026-10-22) DAY_NUM="Day 7";  DAY_TASK="端到端验证" ;;
  2026-10-23) DAY_NUM="Day 8";  DAY_TASK="健康检查 + 冷启动" ;;
  2026-10-26) DAY_NUM="Day 9";  DAY_TASK="故障注入与恢复" ;;
  2026-10-27) DAY_NUM="Day 10"; DAY_TASK="Makefile 与构建脚本" ;;
  2026-10-28) DAY_NUM="Day 11"; DAY_TASK="镜像标签 + 配置外置" ;;
  2026-10-29) DAY_NUM="Day 12"; DAY_TASK="CI 流水线脚本" ;;
  2026-10-30) DAY_NUM="Day 13"; DAY_TASK="收尾 + ADR + 提交" ;;
esac

# ── 生成文件 ────────────────────────────────────────────────────────
sed \
  -e "s|[{][{]DATE[}][}]|${DATE}|g" \
  -e "s|[{][{]WEEKDAY[}][}]|${WEEKDAY}|g" \
  -e "s|[{][{]DAY_NUM[}][}]|${DAY_NUM}|g" \
  -e "s|[{][{]DAY_TASK[}][}]|${DAY_TASK}|g" \
  "${TEMPLATE}" > "${TARGET}"

echo "已生成：${TARGET}"
echo "  ${DAY_NUM} · 星期${WEEKDAY} · ${DAY_TASK}"
echo ""
echo "下一步：打开文件，把计划文档对应 ${DAY_NUM} 章节的"
echo "「目标 + 验收标准」复制到「一、今日计划」。"
