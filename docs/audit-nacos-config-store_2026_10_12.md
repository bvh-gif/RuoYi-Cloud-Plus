# Nacos 配置存储核查（2026-10-12）

> 执行环境：Git Bash on Windows；对象为**当前运行中的** nacos / mysql / redis 容器（由旧副本 B 拉起）。
> 原则：只记录本次实际执行的命令与输出。未验证的部分明确标注「推断」。

## 结论先行

**Nacos 被配置为使用 MySQL 存储配置，但那个库在 MySQL 里并不存在。**
同时 `script/config/nacos/*.yml` 里的配置**尚未导入** Nacos。
业务服务声明的是 `optional:nacos:...`，配置缺失时**静默跳过、不报错**——所以这个问题不会有任何显性症状，只表现为"服务起来了但行为和预期不一致"。

## 证据

| # | 检查 | 命令 | 实际输出 |
|---|---|---|---|
| 1 | Nacos 声明的配置库 | `docker exec nacos sh -c 'echo "$MYSQL_SERVICE_DB_NAME"'` | `nacos` |
| 2 | Nacos 是否有外部 MySQL 配置 | `docker exec nacos sh -c 'env \| cut -d= -f1' \| grep -iE "mysql\|db"` | 存在 `MYSQL_SERVICE_HOST` / `MYSQL_SERVICE_USER` / `MYSQL_SERVICE_PASSWORD` / `MYSQL_SERVICE_DB_NAME` |
| 3 | MySQL 里实际有哪些库 | `SHOW DATABASES` | `information_schema`、`mysql`、`performance_schema`、`ry-cloud`、`sys` —— **没有 `nacos`** |
| 4 | 读配置库 | `SELECT COUNT(*) FROM config_info`（库 nacos） | `ERROR 1049 (42000): Unknown database 'nacos'` |
| 5 | 按 dataId 取配置 | `GET /nacos/v1/cs/configs?dataId=application-common.yml&group=DEFAULT_GROUP` | HTTP 404，body = `config data not exist` |
| 6 | 控制台 API | `GET /nacos/v3/admin/cs/config/list` | HTTP 403（`User not found`）→ 需鉴权；`nacos/nacos` 无效 |
| 7 | 旧版控制台 API | `GET /nacos/v1/cs/configs`（列表） | HTTP 410 Gone，提示改用 `/nacos/v3/console/cs/config/list` |
| 8 | Nacos 数据目录 | `docker inspect` 挂载 | `/mnt/d/dev/agent/.../script/docker/nacos/data -> /home/nacos/data`（**已挂到宿主机**） |
| 9 | derby-data | `ls -la /home/nacos/data/derby-data` | 存在，但所有文件时间均为容器启动时刻 `Oct 10 01:30`，无后续写入迹象 |

## 推断（未完全证实，需继续查）

1. Nacos 大概率**回退到了嵌入式 Derby**（`/home/nacos/data/derby-data` 存在），而不是连上 MySQL。
   依据：目标库不存在 + derby 目录存在。尚未从日志中找到明确的 `storage mode` 输出来坐实。
2. 控制台管理员凭据**不是** `nacos/nacos`。注意：`pom.xml` 里的 `nacos.username/password = nacos/nacos` 是**客户端**访问用的，与控制台管理员账号不是一回事。
3. B 副本里未跟踪的 `script/docker/nacos-mysql.sql` 很可能就是建库脚本，但**尚未执行**——这解释了第 3 条。

## 对之前一个说法的修正

我在 2026-10-10 的 `baseline-audit` 里写过"Nacos 是 standalone 且看不出配了外部 MySQL，配置可能没持久化"。
这句话**需要更正**：Nacos **确实配置了外部 MySQL**，且数据目录已挂载到宿主机，所以不会因为删容器丢失。
真实的问题不是"会丢"，而是"**库建了没、配置导了没**"——目前看起来都没有。

## 下一步（按风险排序）

1. 确认 Nacos 实际存储模式：查启动日志中 `storage mode` / 数据源初始化行。
2. 建库并导入：执行 B 副本里的 `nacos-mysql.sql`（先审查内容），或在 MySQL 中创建 `nacos` 库后重启 Nacos。
3. 导入 `script/config/nacos/*.yml`（application-common、datasource、各 `ruoyi-*.yml`）到 Nacos，命名空间 `public`、组 `DEFAULT_GROUP`。
4. 记录控制台管理员账号密码，否则后续无法备份配置。

## 风险提示

第 2、3 步会**写入数据库与 Nacos**。执行前应先备份 MySQL 的 `ry-cloud`（业务库），
并确认目标 Nacos 就是你打算长期用的那一套（当前这套由旧副本 B 拉起，与新仓库 A 的 compose 不一致）。
