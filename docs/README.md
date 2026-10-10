# docs 目录索引与交接入口

> 最后更新：2026-10-10
> 面向：第一次接手本仓库的人
> 读法：按「一 → 二 → 三 → 四」顺序读，前三步读完就可以安全动手。

---

## 一、先搞清楚：你现在面对的是哪一份代码

**这是最容易踩的坑，务必先确认。**

本仓库存在**两份独立的 Git 仓库**，不是同一个工作树：

| 编号 | 路径 | 分支 | HEAD | origin 指向 | 网络模式 |
|---|---|---|---|---|---|
| **A**（新，本目录） | `D:\dev\project\RuoYi-Cloud-Plus` | `docs/project-progress` | `38d96ffd9` | `bvh-gif/RuoYi-Cloud-Plus`（个人 Fork） | host |
| **B**（旧） | `D:\dev\agent\RuoYi\RuoYi-Cloud-Plus` | `6.X` | `5e98cef44` | `dromara/RuoYi-Cloud-Plus`（**官方上游**） | bridge（`docker_default`） |

- B 落后 A 约 7 周，且承载了**未提交**的工程化成果（Makefile、bridge 版 compose、SQL 脚本等）。
- **当前运行中的 mysql / redis / nacos 是 B 拉起来的**，不是 A。
- 在 B 目录里执行 `git push` 会推向**官方上游**（无权限会失败，但配置语义是错的）。

确认命令（在目标目录执行）：

```bash
git rev-parse --show-toplevel    # 确认仓库根目录
git remote -v                    # 确认 origin 是不是官方
docker inspect <容器名> --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}'
```

---

## 二、文档清单与阅读顺序

| 顺序 | 文件 | 作用 | 什么时候读 |
|---|---|---|---|
| 1 | `project-progress.md` | 目标、阶段 A–D 清单、里程碑验收原则 | 第一次接手，先建立目标感 |
| 2 | `project-progress_2026_10_10.md` | 16 个工作项（BASE/REL/DATA/UI/PIPE/OBS/REC/SEC/AGENT）、状态定义、M0–M4 | 想知道"下一步做什么" |
| 3 | `development-standards_2026_10_10.md` | 17 节团队开发规范（Git / 安全 / 任务 / 测试 / ADR） | 动手前，这是约束条件 |
| 4 | `baseline-audit_2026_10_10.md` | 双副本核实结论 + 3 个 P0 风险 | 想知道"现状到底什么样" |
| 5 | `task-step1-readiness_2026_10_10.md` | 就绪信号任务的验收记录与实跑证据 | 要接手基础设施工作 |
| 6 | `adr/0001-就绪优先与compose叠加层.md` | 两个关键架构决策及其取舍 | 想理解"为什么这么做" |

---

## 三、脚本与配置清单

| 文件 | 作用 | 怎么用 |
|---|---|---|
| `script/docker/readiness.sh` | 依赖就绪检查（MySQL/Redis/Nacos），带超时与退出码 | `bash script/docker/readiness.sh --wait 120` |
| `script/docker/docker-compose.health.yml` | 健康检查/重启策略/依赖，**叠加层** | `docker compose -f docker-compose.yml -f docker-compose.health.yml up -d` |

**重要**：叠加层**不会自动生效**。直接 `docker compose up -d` 不会加载它，且**不报错**。必须显式写两个 `-f`。

退出码：`0` 就绪 / `1` 参数错 / `2` Docker 不可用 / `3` 等待超时 / `4` 检查失败。

---

## 四、2026-10-10 本次变更

| 变更 | 状态 | 说明 |
|---|---|---|
| 新增 readiness.sh | 未入库 | 已实跑验证，通过/失败路径均有证据 |
| 新增 docker-compose.health.yml | 未入库 | `config -q` 校验通过，30 个 service |
| 新增两份文档 | 未入库 | baseline-audit、task-step1-readiness |
| 新增 ADR-0001 | 未入库 | 记录两个架构决策 |
| 修改 `../ruoyi-git-setup.sh` | 在仓库外 | 修正"origin 指向他人 fork"的错误判断（bvh-gif 就是本人 Fork） |

**截至整理时点，以上全部未提交。** 接手的人看不到任何历史，请先提交再继续。

---

## 五、三个必须知道的环境事实（会反复绊人）

1. **Redis 设了口令，且配置文件是 CRLF**。`redis-cli ping` 返回 `NOAUTH`；从 `redis.conf` 提取口令时必须 `tr -d '\r'`，否则尾部回车导致 `WRONGPASS`。
2. **Nacos 3.x 没有 `/actuator/health`**（404），`/nacos/v1/console/health/*` 返回 410 Gone。可用判据：`/nacos/index.html` + 命名服务 API `/nacos/v1/ns/instance/list`。
3. **Nacos 地址在构建期写死**。`pom.xml` 的 dev/prod 两个 profile 的 `nacos.server` 都是 `127.0.0.1:8848`，通过 `@nacos.server@` 打进 jar。运行时改地址用 `SPRING_CLOUD_NACOS_SERVER_ADDR`，不必重新打包。

---

## 六、未完成 / 待验收

- [ ] 就绪检查尚未做**冷启动**验证（`down` → `up`），`start_period` 是否合理未确认
- [ ] `seata` / `minio` / `elasticsearch` 未覆盖健康检查
- [ ] 本次全部变更未提交到版本库
- [ ] A 与 B 两份仓库的分叉未收敛
- [ ] Nacos 配置是否持久化到 MySQL 未确认（standalone 无外部 DB 时有丢失风险）
