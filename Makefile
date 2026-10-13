# RuoYi-Cloud-Plus 统一任务入口
#
# 两组任务：
#   Maven 构建组  online / offline / verify
#   Docker 服务组  dev / check-docker / check-services / status
#
# ── 为什么 Maven 入口固定用 ./mvnw ────────────────────────────────
#   本机 scoop 安装的全局 Maven，其 conf/settings.xml 把本地仓库指向
#   D:\dev\repo\maven-repo —— 那份缓存缺本项目需要的 BOM，直接敲 `mvn` 会踩进去。
#   ./mvnw 的 Maven 版本由项目锁定，仓库走 ~/.m2/repository。
#   （另有用户级 ~/.m2/settings.xml 兜底，即使误用 `mvn` 也已收敛到同一仓库。）
#
# ── online 与 offline 的语义差别（关键）───────────────────────────
#   online   联网。把缺失的依赖与插件下载回来，完整构建到 install。
#            顺带产出各模块 target/*.jar —— Docker 镜像构建需要的就是它。
#   offline  断网。-o 禁止一切网络请求，本地缺一个 jar 就立刻失败、不尝试补。
#            这才是「缓存是否自足」的唯一可靠验收：
#            联网成功只证明『能拿到』，断网成功才证明『已经在手』。
#
# ── 用法 ──────────────────────────────────────────────────────────
#   make online    联网补货 + 编译 + 打包 + install
#   make offline   断网验收，缺 jar 立刻失败
#   make verify    打印当前生效的 Maven 与本地仓库路径（排错首选）
#   make dev       检查 Docker 并拉起依赖服务（对标原 make dev）
#   make status    查看当前服务状态
#
# ── 关于 make 本身 ────────────────────────────────────────────────
#   Windows 侧未安装 make（`scoop install make` 可装）；WSL 发行版自带。
#   两种环境下都可直接使用本文件。
#   Windows 侧暂无 make 时的等价入口：./script/build.sh online | offline | verify
#   （注意：在 WSL 里执行时会用 WSL 自己的 ~/.m2/repository，与 Windows 侧不共享。）

MVNW  := ./mvnw
SKIP  := -DskipTests
GOAL  := clean install

# Docker 服务组：compose 采用三层叠加，与当前生效配置一致
# （script/docker/{docker-compose,docker-compose.health,docker-compose.local}.yml）
COMPOSE_DIR   := script/docker
COMPOSE_FILES := -f docker-compose.yml -f docker-compose.health.yml -f docker-compose.local.yml
SERVICES      := nacos seata-server mysql redis

.DEFAULT_GOAL := help
.PHONY: help online offline verify dev check-docker check-services status

help:
	@echo ""
	@echo "  Maven 构建"
	@echo "    make online    联网：补依赖 + 编译 + 打包 + install"
	@echo "    make offline   离线：-o 断网验收，缺 jar 立刻失败"
	@echo "    make verify    打印生效的 Maven 与本地仓库路径"
	@echo ""
	@echo "  Docker 服务"
	@echo "    make dev       检查 Docker 并拉起依赖服务"
	@echo "    make status    查看当前服务状态"
	@echo ""

# ── Maven 构建组 ─────────────────────────────────────────────────
online:
	$(MVNW) $(GOAL) $(SKIP)

offline:
	$(MVNW) -o $(GOAL) $(SKIP)

verify:
	@$(MVNW) -v 2>&1 | head -1
	@printf "localRepository: "
	@$(MVNW) -q help:evaluate -Dexpression=settings.localRepository -DforceStdout
	@echo ""

# ── Docker 服务组（原 make dev 逻辑，compose 路径改为显式三层叠加）──
dev: check-docker check-services status

check-docker:
	@echo "==> Checking Docker..."
	@if ! docker info >/dev/null 2>&1; then \
		echo "ERROR: Docker is not running."; \
		echo "Please start Docker first."; \
		exit 1; \
	fi
	@echo "Docker is running."

check-services:
	@echo "==> Checking services..."
	@for service in $(SERVICES); do \
		if docker ps --format '{{.Names}}' | grep -qx "$$service"; then \
			echo "[OK]      $$service is running"; \
		else \
			echo "[MISSING] $$service is not running"; \
			echo "          Starting $$service..."; \
			(cd $(COMPOSE_DIR) && docker compose $(COMPOSE_FILES) up -d $$service); \
		fi \
	done

status:
	@echo ""
	@echo "==> Current service status"
	@(cd $(COMPOSE_DIR) && docker compose $(COMPOSE_FILES) ps)
