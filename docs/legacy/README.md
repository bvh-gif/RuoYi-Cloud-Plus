# 旧方案（副本 B）做了什么、为什么不再直接沿用

> 整理日期：2026-10-12
> 来源：`D:\dev\agent\RuoYi\RuoYi-Cloud-Plus`（下文称"副本 B"）
> 目的：保留调试经验与可复用素材，**不是**为了把旧设计搬进新方案。
> 原则：本文件区分「已核实」与「推断」。未打开文件确认的内容一律标注推断。

---

## 一、副本 B 是什么

另一个**独立的 Git 仓库**，不是本仓库的分支或子目录。

| 项 | 副本 B | 本仓库（A） |
|---|---|---|
| 路径 | `D:\dev\agent\RuoYi\RuoYi-Cloud-Plus` | `D:\dev\project\RuoYi-Cloud-Plus` |
| HEAD | `5e98cef44`（2026-08-21） | `a319a6861`（2026-10-09） |
| 与 A 的关系 | B 是 A 的祖先（`merge-base --is-ancestor` 为真），落后约 7 周 | — |
| origin | `dromara/RuoYi-Cloud-Plus`（**官方上游**，配置错误） | `bvh-gif/RuoYi-Cloud-Plus`（个人 Fork） |
| compose 网络 | bridge（`docker_default`） | host |
| 工作区 | 6 个已修改 + 19 项未跟踪 | 干净 |

**当前运行中的 mysql / redis / nacos 由副本 B 拉起**，证据是容器标签
`com.docker.compose.project.config_files = /mnt/d/dev/agent/RuoYi/RuoYi-Cloud-Plus/script/docker/docker-compose.yml`。

---

## 二、旧方案做了什么（按类型）

### 1. 基础设施改造（已核实）

`b-worktree-tracked-changes.patch` 记录了 6 个受版本控制文件的改动，合计 +116 / −223：

| 文件 | 改动 | 说明 |
|---|---|---|
| `pom.xml` | +47 | 新增构建相关配置（**推断**：本地构建镜像所需） |
| `script/docker/docker-compose.yml` | +51 / −? | 加了 healthcheck、restart、端口发布，compose 网络改为 bridge |
| `script/config/nacos/application-common.yml` | 28 处 | Nacos 公共配置调整 |
| `script/config/nacos/seata-server.properties` | 23 处 | Seata 配置调整 |
| `script/docker/redis/conf/redis.conf` | +1 | 就是那行 `requirepass`（**已核实**：正是它导致裸 PING 返回 NOAUTH） |
| `script/docker/seata/conf/application.yml` | **−189（整段删除）** | 意图不明，**需确认是否有意** |

### 2. 手搓的运维脚本与配置（已核实文件存在与体积）

| 文件 | 大小 | 内容（已核实部分） |
|---|---|---|
| `artifacts/Makefile` | 4K | 目标仅 4 个：`dev`、`check-docker`、`check-services`、`status` |
| `artifacts/docker-compose-bridge.yml` | 20K | 30 个 service。⚠️ **名不副实**：实测其中 `network_mode` 出现 30 次、`networks:` 段 0 个，**并未真正实现 bridge** |
| `artifacts/Dockerfile.seata` | 1K | 自建 Seata 镜像 |
| `artifacts/seata-conf/application_{nacos,org,backfile}.yml` | 各 8K | Seata 配置的三个变体（推测分别对应"接 Nacos""原始""备份"） |

### 3. 数据库脚本（已核实）

| 文件 | 实际内容 |
|---|---|
| `sql/mysql-schema.sql` | **Nacos 的 MySQL 建表脚本**（Alibaba 版权头）。这正是"建 nacos 库"所需的脚本 |
| `sql/seata-mysql.sql` | Seata 的 MySQL 建表脚本（Apache 版权头） |
| `sql/nacos-mysql.sql` | ⚠️ **内容是 `404: Not Found`** —— 一次失败的下载产物，不是 SQL |
| `sql/nacos_backup_20260831.sql` | 24K，Nacos 数据备份（**推断**，未打开确认） |
| `sql/mysql-schema-from-image.sql` | 20K，从镜像导出的库结构（**推断**） |

### 4. Nacos 配置导出（已核实）

`artifacts/nacos-config-export/nacos.zip`（2026-08-22）内含：

```
seata-server.properties   application-common.yml   datasource.yml
ruoyi-ai.yml   ruoyi-auth.yml   ruoyi-gateway.yml   ruoyi-gen.yml  ...
```

即**当时 Nacos 里真实生效过的配置快照**。这是新方案导入配置时最直接的参考。

### 5. 部署复盘（最有价值）

`re.md`（16K）是一份完整的部署问题复盘，含"问题现象 / 根本原因 / 解决方案"表格，
覆盖 Docker+WSL2 集成、镜像拉取失败等典型问题。**这是整个归档里最该先读的文件。**

---

## 三、为什么不再直接沿用

不是因为旧方案错，而是因为它**已经无法作为继续推进的基座**：

1. **数据是空的（已核实）** —— MySQL 的 `ry-cloud` 库 **0 张表**；Redis 数据目录仅 4K；Nacos 无配置、无注册实例。跑着的三个容器是"空壳"，不是可用环境。
2. **与上游分叉且无验收（已核实）** —— HEAD 落后 7 周；改动全部未提交，历史里看不到任何痕迹。
3. **origin 指向官方上游（已核实）** —— 在 B 目录里 `git push` 会推向 dromara，违反团队规范 §2.1。
4. **一次关键尝试失败了（已核实）** —— `nacos-mysql.sql` 内容是 `404: Not Found`，说明"给 Nacos 建库"这一步当时没做成，这解释了为什么现在 Nacos 没有配置库。
5. **bridge 改造名不副实（已核实）** —— `docker-compose-bridge.yml` 里仍是 `network_mode` 30 处、`networks:` 0 个，不能直接当作迁移成果接管。

---

## 四、哪些值得在新方案里重新参考

| 旧内容 | 新方案怎么用 |
|---|---|
| `re.md` 部署复盘 | **直接读**，能省掉大量重复踩坑 |
| `sql/mysql-schema.sql` | 建 `nacos` 库时用（注意与 Nacos 版本对应） |
| `sql/seata-mysql.sql` | 建 Seata 库时用 |
| `nacos-config-export/nacos.zip` | 导入 Nacos 配置时的基准（需与 `script/config/nacos/*.yml` 对比后再用） |
| `Makefile` 的 4 个目标 | 参考其形态，但要按新规范重写（补 `help`、`test`、`build`、`logs`，并做退出码传播） |
| Redis `requirepass` 那一行 | 保留需求，但**要重新写**，并处理 CRLF 问题 |
| `seata/conf/application.yml` 被删的 189 行 | **先确认意图**，再决定恢复还是就此放弃 |

**不要直接搬的**：`docker-compose-bridge.yml`（并非真正的 bridge 实现）、`nacos-mysql.sql`（404 产物）、任何运行时数据目录。

---

## 五、归档清单与原始位置

| 归档位置 | 原始路径 |
|---|---|
| `b-worktree-tracked-changes.patch` | B 的 `git diff` 输出（6 个受控文件改动） |
| `manifest.txt` | B 的改动统计与未跟踪文件清单 |
| `re.md` | `D:\dev\agent\RuoYi\RuoYi-Cloud-Plus\re.md` |
| `artifacts/*` | `D:\dev\agent\RuoYi\RuoYi-Cloud-Plus\script\docker\*` 下对应位置 |
| `artifacts/nacos-config-export/nacos.zip` | `…\script\config\nacos\nacos.zip` |

**未归档（有意排除）**：容器运行时数据（`nacos/data` 239M、`seata/logs` 39M、`redis/data`、`seata/libs`），
因为它们是无价值的进程产物，且体积大。

---

## 六、下一步

1. 读 `re.md`，把仍然适用的条目摘进 `development-standards`。
2. 建 `nacos` 库：用 `sql/mysql-schema.sql`，并**先确认它与 Nacos 3.2.3 版本匹配**。
3. 导入配置：以 `nacos-config-export/nacos.zip` 为参考，与 `script/config/nacos/*.yml` 对比后决定。
4. 确认 `seata/conf/application.yml` 被删除 189 行是否有意。
