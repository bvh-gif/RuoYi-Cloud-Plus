.PHONY: dev check-docker check-service start-services status

# 需要检查的服务
SERVICES := nacos seata-server mysql redis

# 默认目标
dev: check-docker check-services status

# 检查 Docker 是否运行
check-docker:
	@echo "==> Checking Docker..."
	@if ! docker info >/dev/null 2>&1; then \
		echo "ERROR: Docker is not running."; \
		echo "Please start Docker first."; \
		exit 1; \
	fi
	@echo "Docker is running."

# 检查所有服务
check-services:
	@echo "==> Checking services..."
	@for service in $(SERVICES); do \
		if docker ps --format '{{.Names}}' | grep -qx "$$service"; then \
			echo "[OK]      $$service is running"; \
		else \
			echo "[MISSING] $$service is not running"; \
			echo "          Starting $$service..."; \
			docker compose up -d $$service; \
		fi \
	done

# 查看最终状态
status:
	@echo ""
	@echo "==> Current service status"
	@docker compose ps