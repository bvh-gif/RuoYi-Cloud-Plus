#!/usr/bin/env bash
# 与根目录 Makefile 等价的构建入口 —— 本机未安装 make 时使用。
#
#   online   联网补货 + 编译 + 打包 + install，产出各模块 target/*.jar
#   offline  断网验收：-o 禁止一切网络，本地缺一个 jar 就立刻失败
#   verify   打印当前生效的 Maven 与本地仓库路径（排错首选）
#
# 用法：./script/build.sh {online|offline|verify}

set -euo pipefail
cd "$(dirname "$0")/.."

MVNW=./mvnw
SKIP=-DskipTests

case "${1:-help}" in
  online)
    $MVNW clean install $SKIP
    ;;
  offline)
    $MVNW -o clean install $SKIP
    ;;
  verify)
    $MVNW -v 2>&1 | head -1
    printf "localRepository: %s\n" \
      "$($MVNW -q help:evaluate -Dexpression=settings.localRepository -DforceStdout)"
    ;;
  *)
    echo "用法: $0 {online|offline|verify}" >&2
    exit 1
    ;;
esac
