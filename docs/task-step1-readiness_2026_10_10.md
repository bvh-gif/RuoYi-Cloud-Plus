# [REL-00] 本地依赖就绪信号

- 状态：待验收
- 优先级：P0
- 负责人：bvh-gif
- 日期：2026-10-10

## 背景

原 `docker-compose.yml` 中 `healthcheck` 数量为 **0**、`restart` 数量为 **0**，业务服务也没有 `depends_on`。
这种情况下无法回答"某个服务到底能不能用"，后续任何自动化（流水线、恢复、重试）都缺少判定基准。

## 目标

1. 为 MySQL / Redis / Nacos 提供匹配自身能力的容器级健康检查。
2. 业务服务声明依赖与重启策略。
3. 提供一个退出码语义明确的命令行就绪检查入口。

## 非目标

- 不改网络模式（host → bridge 属于独立任务，本任务未触及）。
- 不改 `docker-compose.yml` 原文件。
- 不做镜像构建、部署或前端发布。

## 实施方案

采用 **overlay** 方式：新增 `docker-compose.health.yml`，使用时叠加。

```bash
docker compose -f docker-compose.yml -f docker-compose.health.yml up -d
```

| 文件 | 作用 |
|---|---|
| `script/docker/docker-compose.health.yml` | healthcheck + restart + 业务服务 depends_on |
| `script/docker/readiness.sh` | 宿主机侧就绪检查，真实能力探测 + 有限轮询 + 明确退出码 |

## 检查内容与设计取舍

| 依赖 | 检查方式 | 为什么这样做 |
|---|---|---|
| MySQL | 容器内用自身环境变量凭据执行 `SELECT 1` | 只看端口可达会漏掉认证失败；mysqladmin ping 在密码错误时仍返回成功 |
| Redis | 从挂载的 redis.conf 读取 requirepass 后 `PING` | 本项目 Redis **已启用口令**，裸 PING 返回 `NOAUTH` |
| Nacos | 宿主机访问控制台 + 调用命名服务 API `/nacos/v1/ns/instance/list` | 实测 Nacos 3.x **没有** `/actuator/health`（404），控制台 health 端点返回 410 Gone |
| 服务发现 | `--expect <service>` 检查注册实例数 > 0 | 控制台能打开 ≠ 有服务注册成功 |

允许用 `--expect` 校验指定服务是否已注册，这是"服务发现真正生效"的判据。

## 退出码

| 码 | 含义 |
|---|---|
| 0 | 全部就绪 |
| 1 | 参数错误 |
| 2 | Docker / Compose 不可用 |
| 3 | 等待超时 |
| 4 | 检查失败 |

## 验收证据（2026-10-10 实跑）

环境：Docker 29.3.1 / Compose v5.1.1；运行中容器 mysql、redis、nacos。

```text
$ bash script/docker/readiness.sh
OK      mysql        认证成功，SELECT 1 通过
OK      redis        PING 返回 PONG
OK      nacos        控制台与命名服务 API 均可用
全部就绪。
退出码=0
```

失败路径：

| 场景 | 命令 | 退出码 | 期望 |
|---|---|---|---|
| 要求服务已注册但无业务服务 | `readiness.sh --expect ruoyi-system` | 4 | 4 |
| 等待超时 | `readiness.sh --expect ruoyi-auth --wait 5 --interval 2` | 3 | 3 |
| 容器不存在 | `MYSQL_CT=nosuchct readiness.sh` | 4 | 4 |
| 参数错误 | `readiness.sh --bogus` | 1 | 1 |
| 等待后立即成功 | `readiness.sh --wait 10` | 0 | 0 |

Compose 叠加层语法校验：

```text
$ docker compose -f docker-compose.yml -f docker-compose.health.yml config -q
退出码=0，30 个 service
```

## 本次发现的新事实（此前文档未记载）

1. **Redis 已启用 requirepass**，且 `script/docker/redis/conf/redis.conf` 是 **CRLF 换行**。
   `awk` 取出的口令带 `\r`，导致 `redis-cli -a` 报 `WRONGPASS`。健康检查必须先 `tr -d '\r'`。
2. **Nacos 3.1.2 没有 `/actuator/health`**（404），`/nacos/v1/console/health/*` 返回 410 Gone。
   可用的就绪判据是 `/nacos/index.html`（200）配合命名服务 API。
3. **当前运行环境来自旧副本**：运行中的 mysql/redis/nacos 的
   `com.docker.compose.project.config_files` 指向
   `/mnt/d/dev/agent/RuoYi/RuoYi-Cloud-Plus/script/docker/docker-compose.yml`，
   网络为 `docker_default`（bridge），且已发布了 8848/3306/6379 端口。
   而新仓库 `script/docker/docker-compose.yml` 是 **host 网络**、无端口映射。
   **两者不一致**，迁移与排障时必须先确认目标是哪一套。
4. 运行中的 nacos 镜像是 `v3.1.2`，新仓库 compose 写的是 `v3.2.3`。

## 风险与遗留

- healthcheck 尚未在真实冷启动（`down` → `up`）场景下验证，仅在已运行容器上验证。
  下一步应销毁后重跑，确认 `start_period` 设置合理。
- `restart: unless-stopped` 会掩盖崩溃循环；排查时需注意容器可能被自动拉起。
- overlay 文件尚未提交到版本库，当前为未跟踪状态。

## 下一步

1. 冷启动一次，验证 depends_on 编排顺序确实生效。
2. 补 `ruoyi-seata-server`、`minio`、`elasticsearch` 的健康检查（当前未覆盖）。
3. 将 overlay 与脚本纳入 `Makefile` 的 `status` / `wait` 目标。
