# 每日工作计划：在 WSL2 + Docker 上跑通 RuoYi-Cloud-Plus

> 制定日期：2026-10-13
> 最终目标：**在 WSL2 上用 Docker 完整跑起来**，并沉淀出可迁移到 DevOps 平台的工程资产
> 当前分支：`docs/project-progress`
> 标注约定：`[事实]` 已实测确认 · `[推断]` 基于证据的推测 · `[建议]` 我的主张
>
> **本月排期**：10/13 – 10/31 共 14 个工作日，映射到 Day 0 – Day 13。
> 已排除国庆假期（10/1–10/7）、调休上班日（10/10）与 3 个周末，明细见 [第四章](#四月历排期2026-年-10-月)。
> 关键路径：**10/14 构建 → 10/15 打镜像 → 10/20 bridge 迁移 → 10/22 端到端验证**。

---

## 〇、结论先行

要跑起来，**只有一条无法绕过的链路**：

```
Maven 构建出 jar → docker build 出镜像 → 镜像注册进 Nacos → 网关可路由 → 浏览器可访问
```

当前这条链路**在第 1 步就断了**（无 jar、无镜像），且**网络模式是第二个硬阻塞**：

| 阻塞项 | 实测证据 | 影响 |
|---|---|---|
| **无业务镜像** | 本地只有无关的 `ruoyi-app:v1`，`ruoyi/ruoyi-*:6.0.0` 一个都没有 | 11 个业务服务全部起不来 |
| **无构建产物** | `find . -path "*/target/*.jar"` 为空 | 镜像无从构建 |
| **Maven 构建失败** | `.local-data/logs/mvn-build.log`：`Remote host terminated the handshake` / `SSL peer shut down incorrectly` | 阻塞第一步 |
| **host 网络 Windows 侧不可达** | `curl localhost:8848` → 10061 拒绝；`curl 192.168.65.3:8848` → 000；容器内 `127.0.0.1:8848` → **200** | 浏览器无法访问任何服务 |

**因此本计划的核心不是"改配置"，而是"先把镜像造出来，再把网络改对"。**

---

## 一、现状盘点（2026-10-13 实测）

### 1.1 已就绪

| 项 | 状态 | 证据 |
|---|---|---|
| 基础三件套 | mysql / redis / nacos 运行中且 `healthy` | `docker ps` |
| 容器来源 | 来自**本仓库 A** 的三层叠加 compose | `config_files` = `D:\dev\project\RuoYi-Cloud-Plus\script\docker\docker-compose.yml` + `.health.yml` + `.local.yml` |
| 数据卷重定向 | `.local-data/` 已生效，含 mysql 数据 | `RUOYI_DATA_ROOT=D:/dev/project/RuoYi-Cloud-Plus/.local-data` |
| 业务库 | `ry-cloud` 已初始化 | `.local-data/mysql/data/ry@002dcloud/` 存在 |
| Dockerfile | 12 个业务模块齐全 | `ruoyi-auth` `ruoyi-gateway` + 7 个 modules + monitor / snailjob / snailai |
| 就绪检查脚本 | `readiness.sh` 已实跑验证，退出码语义完备 | `task-step1-readiness_2026_10_10.md` |
| Nacos 配置源 | `script/config/nacos/` 下 15 个 yml + 1 个 properties | 待导入 |

### 1.2 修正两处过时结论

> 上一轮文档（`docs/README.md`、`task-step1-readiness_2026_10_10.md`）写于 10-10，以下两点**已被本次实测推翻**：

| 旧结论 | 实测结果 | 处理 |
|---|---|---|
| "当前运行中的 mysql/redis/nacos 是**旧副本 B** 拉起来的" | `[事实]` 实际来自**本仓库 A** 的 compose（见 1.1） | 文档需更正，否则排障时找错目录 |
| "Nacos 3.x 可用判据是 `/nacos/v1/ns/instance/list`" | `[事实]` v3.2.3 的 `/nacos/v1/cs/configs` 已返回 **404**（`No endpoint GET`） | 配置导入脚本须改用 **v3 Open API** |

### 1.3 关键架构事实

| 事实 | 值 | 为什么重要 |
|---|---|---|
| 服务总数 | 30 个（compose 中 28 service + 已运行 3 个） | 全量启动资源开销大，建议分组启动 |
| 网络模式 | **全部** `network_mode: "host"` | 见下方深度分析 |
| Nacos 版本 | `nacos/nacos-server:v3.2.3` | API 路径与 2.x 不同 |
| Nacos 地址 | 构建期烘焙 `@nacos.server@` = `127.0.0.1:8848` | 运行时可用 `SPRING_CLOUD_NACOS_SERVER_ADDR` 覆盖，**不必重新打包** |
| 服务发现 | Spring Cloud（`lb://`，网关路由）+ Dubbo（`@DubboService`，服务间调用），共用 Nacos | 两套都要通，缺一不可 |
| 双注册分组 | Spring Cloud 用 `DEFAULT_GROUP`，Dubbo 用 `DUBBO_GROUP` | 导入配置时分组不能填错 |

---

## 二、关键概念：为什么 host 网络在 WSL2 下必须改掉

> 这是本计划最重要的技术判断，值得先花 5 分钟理解。

### 2.1 host 网络的语义

`network_mode: host` 的字面意思是"容器直接用宿主机的网络栈"。

- **在原生 Linux 上**：宿主机 = 你登录的那台机器，容器和你的 shell 共享 `127.0.0.1`，端口直接暴露，一切符合直觉。
- **在 Docker Desktop for Windows（WSL2 后端）上**：宿主机 = 一个名为 `docker-desktop` 的**隐藏 WSL 发行版**。

于是网络被切成三层，彼此**不共享** `127.0.0.1`：

```
┌─ Windows 11 主机 ────────────┐   curl localhost:8848 → 拒绝连接 ✗
│   浏览器在这里                │   curl 192.168.65.3:8848 → 000 ✗
└──────────┬───────────────────┘
           │ （Docker Desktop 只对 bridge 端口映射做转发）
┌──────────▼───────────────────┐
│  docker-desktop 发行版         │  ← network_mode: host 的"宿主机"在这里
│  IP: 192.168.65.3             │    容器 A、B、C 共享此命名空间
│  容器: mysql / nacos / redis  │    容器内 127.0.0.1:8848 → 200 ✓
└───────────────────────────────┘
┌───────────────────────────────┐
│  Ubuntu 发行版（你的 WSL）     │  ← 独立命名空间，独立 IP
│  在这里 curl 127.0.0.1:8848   │    也访问不到 nacos ✗
└───────────────────────────────┘
```

### 2.2 这带来的三个后果

1. **服务之间能通**（都在 `docker-desktop` 命名空间内，`127.0.0.1:8848` 可达）——所以业务服务"能注册进 Nacos"。
2. **Windows 浏览器访问不到任何东西**——`localhost:8848`、`192.168.65.3:8848` 都失败。你无法用浏览器打开 Nacos 控制台，也无法访问网关 8080。
3. **你的 WSL Ubuntu 里也访问不到**——它和 `docker-desktop` 是两个独立发行版。

### 2.3 结论与取舍

| 方案 | 做法 | 优点 | 缺点 | 何时用 |
|---|---|---|---|---|
| **A. 保持 host，容器内验证** | 不改造，`docker exec` 里 curl | 零改动，符合"先验证再迁移" | **浏览器打不开**，无法做真实端到端验证；与 K8s 语义不兼容 | 只想快速确认"服务能不能起来" |
| **B. 迁移 bridge + 端口映射** | 新增 `docker-compose.bridge.yml` 叠加层 | 浏览器可访问；**与 K8s Service 语义一致**，是 DevOps 迁移的正确方向 | 需处理 `@nacos.server@` 烘焙地址（用环境变量覆盖即可） | **推荐**：目标含 DevOps 迁移时 |
| C. host + 手动路由 | 找 VM IP 做端口转发 | 看似折中 | VM IP 会变，脆弱；实测已失败 | 不推荐 |

**决策：采用 B（bridge），但分两步走**（2026-10-13 确认，尊重"先验证再迁移"原则）：
- Day 4 用方案 A 做**最低成本的业务注册验证**（容器内 curl，约半小时），确认"jar 和镜像没问题"；
- Day 5 立刻切方案 B，因为只有 bridge 才能证明"真的跑起来了"。

> 这两步的价值在于**问题隔离**：Day 4 失败 → 问题在 jar/配置；Day 4 成功但 Day 5 失败 → 问题在网络。
> 若跳过 Day 4 直接上 bridge，起不来时就要同时排查镜像、配置、网络三类问题。

> 关键认知：**方案 A 无法证明项目跑起来了**——它只能证明"进程没崩"。真正可访问的判据是浏览器能打开登录页。

---

## 三、每日计划

> 每天的结构统一为：**目标 → 做什么 → 为什么 → 验收标准 → 失败怎么办**。
> 每条命令都标注执行环境：`[WSL-Ubuntu]` / `[Git Bash]` / `[PowerShell]`。
> 标题后的日期对应第四章的排期表。

### Day 0 · 10/13（二）— 计划制定 + 环境准备

**目标**：把代码落到 WSL ext4 原生目录，为明天的构建铺好路。

**做什么**

1. 在 WSL 中 clone 仓库到 `~/workspace/RuoYi-Cloud-Plus`（ext4 原生，非 `/mnt/d`）
2. 迁出当前未提交的改动：
   ```bash
   # [Git Bash] Windows 侧：导出已跟踪文件的改动
   cd /d/dev/project/RuoYi-Cloud-Plus
   git diff > /tmp/wip.patch
   git status --porcelain    # 列出未跟踪文件，供下一步单独拷贝

   # [WSL-Ubuntu] 新目录：应用改动
   cd ~/workspace/RuoYi-Cloud-Plus
   git apply /tmp/wip.patch
   ```
   `[注意]` `git diff` **不包含未跟踪文件**。按 `git status --porcelain` 的结果，
   手动拷贝 `script/docker/.env`、`bootstrap-data.sh`、`.env.bak` 等。
3. 确认工具链：`java -version`（需 21）、`./mvnw -version`
4. 确认 Docker 可访问：`docker version`

**为什么**：Docker 构建上下文若放在 `/mnt/d` 下，每次 `docker build` 都要跨 9P 协议传输
100MB+ 的 jar，12 个模块累计会明显拖慢。**这一步的产出决定明天的构建速度。**

**验收标准**
```bash
cd ~/workspace/RuoYi-Cloud-Plus && git status --porcelain   # 改动已迁过来
./mvnw -version                                              # 能正常执行
df -T . | tail -1                                            # 文件系统应为 ext4，不是 9p
```

**失败怎么办**：`git apply` 冲突 → 用 `git apply --3way` 或手工合并；
`./mvnw` 无执行权限 → `chmod +x mvnw`。

---

### Day 1 · 10/14（三）— 环境地基与 Maven 构建验证 ⚠️ 关键路径

**目标**：确认 WSL 环境可用，并**构建出全部业务 jar**。这是整个计划的地基。

**做什么**

1. **确认代码位置已就位**（Day 0 的产出）

   `[事实]` 代码位置已决策：**`~/workspace/RuoYi-Cloud-Plus`（WSL ext4 原生）**。
   理由：Docker 构建上下文在 `/mnt/d` 下要跨 9P 传输，12 个模块 × 100MB+ jar，
   差距会从"分钟级"变成"十分钟级"。

2. **先锁定构建走的是哪套工具链**（这是上次失败的真正原因，务必先确认）

   `[事实]` 本机存在**两套 Maven 环境**，用错就会失败：

   | 工具链 | 本地仓库 | 3 个关键 BOM | 日志特征 |
   |---|---|---|---|
   | **项目自带 `./mvnw`** ✅ | `~/.m2/repository`（仓库 A） | **全有** | 只出现 `public` + `central` |
   | 系统 scoop `mvn` ❌ | `D:\dev\repo\maven-repo`（仓库 B） | **全缺** | 出现 `aliyunmaven` |

   缺失的 3 个 BOM：`spring-boot-dependencies:4.1.1`、
   `spring-ai-bom:2.0.1`、`sa-token-bom:1.46.0`。

   ```bash
   # [WSL-Ubuntu] 确认走的是 mvnw，而不是系统 mvn
   cd ~/workspace/RuoYi-Cloud-Plus
   ./mvnw -version
   which mvn          # 若指向 scoop 的 mvn，后续命令一律用 ./mvnw，不要裸敲 mvn
   ```

3. **绕开代理**（`[事实]` 当前环境存在 `https_proxy`，会中断 TLS 握手）
   ```bash
   env -u https_proxy -u HTTPS_PROXY -u http_proxy -u HTTP_PROXY ./mvnw -version
   ```

4. **执行构建**
   ```bash
   time env -u https_proxy -u HTTPS_PROXY ./mvnw clean package -DskipTests 2>&1 | tee ~/mvn-build.log
   ```

**为什么**：镜像的 Dockerfile 全部是 `ADD ./target/xxx.jar ./app.jar`——**没有 jar 就没有镜像**，这一步无法跳过。
而上次失败的根因已查明是**用错了仓库**（scoop mvn → 仓库 B，缺 3 个 BOM）**叠加上代理干扰**，
不是依赖本身不存在——所以不要急着换镜像源，先确认走对工具链。

**验收标准**
```bash
find . -path "*/target/*.jar" -not -name "*sources*" | wc -l   # 期望 ≥ 11
grep -c aliyunmaven ~/mvn-build.log     # 期望 0，出现即说明用了 scoop mvn
```

**失败怎么办**

| 症状 | 排查方向 |
|---|---|
| `Remote host terminated the handshake` / `SSL peer shut down incorrectly` | 先确认已 `env -u https_proxy` 绕开代理；再确认用的是 `./mvnw` 而非 scoop `mvn`（日志搜 `aliyunmaven`） |
| 仍缺那 3 个 BOM | 说明走了仓库 B。按记忆中的方案：新增用户级 `~/.m2/settings.xml`，显式声明 `localRepository` 指向仓库 A + `mirrorOf=central` 华为镜像（overlay，不改 scoop 上游文件） |
| 依赖下载极慢 | 华为云镜像偶有波动，可改用阿里云或中央仓库 |
| 编译错误（非依赖问题） | 保存完整日志单独处理，不要阻塞 Day 2 |

**风险提示**：全量构建预计 **20–60 分钟**（首次下载依赖）。建议后台跑并记录日志，期间不要中断。

---

### Day 2 · 10/15（四）— 构建 12 个业务镜像 ⚠️ 关键路径

**目标**：`docker images` 中出现全部 `ruoyi/ruoyi-*:6.0.0`。

**做什么**（`[WSL-Ubuntu]`，在仓库根目录）
```bash
docker build -t ruoyi/ruoyi-gateway:6.0.0        ./ruoyi-gateway
docker build -t ruoyi/ruoyi-auth:6.0.0           ./ruoyi-auth
docker build -t ruoyi/ruoyi-system:6.0.0         ./ruoyi-modules/ruoyi-system
docker build -t ruoyi/ruoyi-gen:6.0.0            ./ruoyi-modules/ruoyi-gen
docker build -t ruoyi/ruoyi-job:6.0.0            ./ruoyi-modules/ruoyi-job
docker build -t ruoyi/ruoyi-resource:6.0.0       ./ruoyi-modules/ruoyi-resource
docker build -t ruoyi/ruoyi-workflow:6.0.0       ./ruoyi-modules/ruoyi-workflow
docker build -t ruoyi/ruoyi-ai:6.0.0             ./ruoyi-modules/ruoyi-ai
docker build -t ruoyi/ruoyi-monitor:6.0.0        ./ruoyi-visual/ruoyi-monitor
docker build -t ruoyi/ruoyi-snailjob-server:6.0.0 ./ruoyi-visual/ruoyi-snailjob-server
docker build -t ruoyi/ruoyi-snailai-server:6.0.0  ./ruoyi-visual/ruoyi-snailai-server
```

**为什么**：compose 里写的是固定镜像名 `ruoyi/ruoyi-*:6.0.0` 且**没有 `build:` 段**——compose 不会帮你构建，必须预先打好且**名字完全对上**。

`[建议]` 把上面这段固化成 `script/docker/build-images.sh`，为后续 CI 复用（DevOps 迁移时流水线直接调它）。

**验收标准**
```bash
docker images --format '{{.Repository}}:{{.Tag}}' | grep -c '^ruoyi/ruoyi-'   # 期望 11
```

**失败怎么办**
- `ADD ./target/ruoyi-system.jar: not found` → jar 名与 Dockerfile 不一致。**注意 gateway 的 jar 名是 `ruoyi-gateway-mvc.jar`**（带 `-mvc` 后缀），逐个核对。
- 构建上下文过大 → 检查是否有 `.dockerignore`（若没有，建议加，排除 `target/` 以外的无关文件）。

---

### Day 3 · 10/16（五）— Nacos 配置导入

**目标**：Nacos 配置中心里有全部业务配置，业务服务启动后能拉到配置。

**做什么**（`[WSL-Ubuntu]`）

把 `script/config/nacos/` 下的 15 个 yml 导入 Nacos。

> ⚠️ **API 路径已变**：`[事实]` Nacos v3.2.3 下 `/nacos/v1/cs/configs` 返回 **404**（`No endpoint GET`）。
> v3 的配置管理 API 前缀为 `/nacos/v3/admin/cs/config`，且**需要鉴权**。
> **导入前必须先实测确认可用端点与鉴权方式**，不要照抄 v2 的脚本。

```bash
# 第一步：确认端点可用性（在 nacos 容器内执行，绕开 host 网络不可达问题）
docker exec nacos curl -s -o /dev/null -w "%{http_code}\n" \
  "http://127.0.0.1:8848/nacos/v3/admin/cs/config?search=accurate&dataId=&group=DEFAULT_GROUP"
```

**导入时需特别注意分组**：

| 文件 | 分组 | 说明 |
|---|---|---|
| `application-common.yml` `datasource.yml` 及各 `ruoyi-*.yml` | `DEFAULT_GROUP` | Spring Cloud 侧 |
| `seata-server.properties` | 按 seata 约定 | 单独处理 |
| Dubbo 相关配置 | `DUBBO_GROUP` | `双分组`不能错，否则 Dubbo 服务找不到配置 |

**为什么**：RuoYi-Cloud-Plus 是**配置中心驱动**的——数据库连接、Redis 地址、路由规则全在 Nacos 里。配置没导入，服务启动会直接失败或连错库。

**验收标准**：列出 Nacos 中的 dataId，与 `script/config/nacos/` 下的文件一一对应（数量与名称）。

**失败怎么办**：若 v3 API 鉴权复杂，**备选方案**是直接用 Nacos 控制台的"导入配置"功能上传 zip（`[建议]` 提前把所有 yml 打成 zip）。前提是浏览器能访问控制台——**这又要求先解决网络问题**，因此 Day 3 和 Day 5 可能需要交换顺序，或用 MySQL 直接写入 `config_info` 表作为兜底。

---

### Day 4 · 10/19（一）— host 网络下的业务注册验证（快速，不做改造）

**目标**：用**最低成本**确认"jar 和镜像是好的"——服务能起来并注册进 Nacos。

**做什么**（`[WSL-Ubuntu]`）
```bash
# 1. 起基础设施（三层叠加）
docker compose -f script/docker/docker-compose.yml \
               -f script/docker/docker-compose.health.yml \
               -f script/docker/docker-compose.local.yml \
               up -d mysql redis nacos

# 2. 等就绪
bash script/docker/readiness.sh --wait 180

# 3. 起网关 + 认证 + 系统
docker compose ... up -d ruoyi-gateway ruoyi-auth ruoyi-system

# 4. 验证注册（注意：v3 的实例查询端点也需确认）
docker exec nacos curl -s "http://127.0.0.1:8848/nacos/v3/admin/ns/instance/list?serviceName=ruoyi-system"
```

**为什么**：这一步**不投入任何改造成本**，纯粹是为了把"镜像/配置"和"网络"两类问题**隔离**。如果这一步就失败，问题在 jar/配置；如果这一步成功而浏览器打不开，问题在网络——排障方向立刻清晰。

**验收标准**：`ruoyi-system`、`ruoyi-auth`、`ruoyi-gateway` 在 Nacos 服务列表中显示为**健康实例**。

**失败怎么办**
- 容器反复重启 → `docker logs <容器>` 看异常。最常见是**连不上 Nacos 或 MySQL 地址错**（配置没导入 / 分组错）。
- 启动时报 `No available service` → Dubbo 侧分组问题。

---

### Day 5 · 10/20（二）— bridge 网络迁移 ⭐ 关键里程碑

**目标**：**Windows 浏览器能打开 Nacos 控制台和网关**。这是"真的跑起来了"的第一个硬证据。

**做什么**

1. 新增叠加层 `script/docker/docker-compose.bridge.yml`（**不改上游文件**，符合 overlay 原则）：
   - 移除 `network_mode: "host"`（`[注意]` Compose 中 `network_mode` 与 `networks` 互斥，叠加层无法直接"取消"它——需要显式覆盖为 `networks: [ruoyi-net]`，并逐个服务写。若叠加层覆盖不掉，则改为复制一份 `docker-compose.bridge.yml` 作为**主文件**使用）
   - 定义 `networks: ruoyi-net: driver: bridge`
   - 为每个服务加端口映射：`8848:8848`、`8080:8080`、`3306:3306`、`6379:6379` 等
2. **改造服务发现地址**：bridge 下 `127.0.0.1` 不再指向 Nacos，需给每个业务服务加环境变量：
   ```yaml
   environment:
     SPRING_CLOUD_NACOS_SERVER_ADDR: nacos:8848
     SPRING_CLOUD_NACOS_DISCOVERY_SERVER_ADDR: nacos:8848
     SPRING_CLOUD_NACOS_CONFIG_SERVER_ADDR: nacos:8848
   ```
   **这里不需要重新打 jar**——环境变量会覆盖烘焙进 jar 的 `@nacos.server@`，这是本方案能成立的关键。
3. 同步更新 Nacos 配置里的 MySQL/Redis 地址（配置中心里的 `datasource.yml` 写的是 `127.0.0.1`，bridge 下要改成容器名 `mysql` / `redis`）。

**验收标准**
- `[PowerShell]` `curl http://localhost:8848/nacos/index.html` → **200**
- 浏览器打开 `http://localhost:8848/nacos` 能看到控制台
- 网关 `http://localhost:8080` 有响应

**失败怎么办**
- 叠加层覆盖不掉 `network_mode` → 改用独立的 bridge 版主文件（这也是旧副本 B 已有的资产，可参考其写法）
- 服务起不来 → 检查环境变量是否覆盖了烘焙地址；检查配置中心里的地址是否还是 `127.0.0.1`

---

### Day 6 · 10/21（三）— 前端构建与部署

**目标**：登录页能通过浏览器打开。

**做什么**
1. 获取 `plus-ui` 前端源码（`[推断]` 本仓库不含前端，需单独 clone；**待确认是否有本地副本**）
2. `pnpm install && pnpm build:prod`，产出 `dist/`
3. 把 `dist/` 挂到 `nginx-web` 容器的静态目录
4. 配置 nginx 反代：静态资源走本地，API 请求转发到网关

**为什么**：RuoYi 是前后端分离的——后端跑通只意味着接口通了，
**用户真正接触的是浏览器**。没有前端，"跑起来"这件事对外是不可见的。

**验收标准**：浏览器打开 `http://localhost`（nginx 80）返回登录页 HTML，静态资源无 404。

**失败怎么办**：前端 404 → 检查 nginx 挂载路径与 `dist` 位置是否一致；
接口 502 → 检查 nginx 到 gateway 的反代地址（bridge 下应为 `ruoyi-gateway:8080`，**不能写 127.0.0.1**）。

---

### Day 7 · 10/22（四）— 端到端验证 ⭐ 本月核心 KPI

**目标**：**真正登录进去并用起来**。这是"跑起来"的最终判据。

**做什么**
1. 打开登录页 → 输入凭证 → 登录
2. 验证核心链路：用户管理、菜单加载、一个业务模块的增删改查
3. 验证服务间调用是否真的走通（Dubbo 链路）：
   打开涉及跨服务调用的页面，确认有数据返回

**为什么**：前面所有步骤都是"进程活着"层面的验证。
**只有登录成功 + 跨服务调用有数据**，才能证明 Spring Cloud 路由和 Dubbo 调用两套服务发现都通了。

**验收标准**
- [ ] 登录成功，进入首页
- [ ] 菜单正常加载（说明 `ruoyi-system` 提供服务正常）
- [ ] 至少一个跨模块页面有数据（说明 Dubbo 调用通）
- [ ] 退出再登录，功能正常（说明会话与缓存正常）

**失败怎么办**
| 症状 | 定位方向 |
|---|---|
| 验证码不出 / 登录 500 | 查 `ruoyi-auth` 日志，多半是 Redis 地址或口令问题 |
| 登录成功但菜单为空 | 查 `ruoyi-system` 是否注册成功、数据库 `sys_menu` 是否有数据 |
| 跨模块页面报错 | 查 Dubbo 分组（应为 `DUBBO_GROUP`）与 Nacos 中对应配置 |

---

### Day 8 · 10/23（五）— 健康检查补全与冷启动验证

---

**目标**：让"服务到底健不健康"这件事**可判定、可复现**。

**做什么**
1. 补 `seata-server`、`minio`、`elasticsearch` 的健康检查（当前 `docker-compose.health.yml` 未覆盖）
2. **冷启动验证**（这是上一轮遗留的未验收项）：
   ```bash
   docker compose ... down
   docker compose ... up -d
   bash script/docker/readiness.sh --wait 300
   ```
   确认 `start_period` 设置合理，不会误判
**验收标准**：`down` → `up` 冷启动后，`readiness.sh --wait 300` 退出码为 **0**，
且各容器在合理时间内变为 `healthy`（`start_period` 设置合理，无误判）。

**为什么**：这是 DevOps 迁移的**前置条件**——平台依赖健康检查做滚动更新和自愈。
没有健康检查，上平台等于裸奔；而**没做过冷启动验证的健康检查，等于没做**。

**失败怎么办**：容器迟迟不变 healthy → 调大 `start_period`；
容器反复重启 → 检查 `restart: unless-stopped` 是否掩盖了崩溃循环（排查时先手动 stop 掉）。

---

### Day 9 · 10/26（一）— 故障注入与可恢复性测试

**目标**：验证"**挂了能自己爬起来**"。

**做什么**
1. `docker stop mysql` → 观察业务服务的降级行为与日志
2. `docker start mysql` → 确认服务自动恢复，无需人工干预
3. 对 `nacos`、`redis` 各做一次同样的注入
4. 记录每次的**恢复耗时**与**是否有数据损坏**

**验收标准**：三次注入后服务均自动恢复；业务数据无丢失；恢复耗时记录在案。

**为什么**：这是从"能跑"到"**敢放上平台**"的分水岭。
平台会自动调度和重启容器，如果服务无法自愈，上平台后故障会被放大。

**失败怎么办**：服务无法自动恢复 → 检查 `depends_on` 是否只写了容器启动顺序
（Compose 的 `depends_on` **默认不等就绪**，需配合 `condition: service_healthy`）。

---

### Day 10 · 10/27（二）— Makefile 与构建脚本固化

**目标**：把散落的命令收拢成**一个入口**，让别人（和 CI）也能跑起来。

**做什么**
1. 新建根目录 `Makefile`（当前**没有**），封装常用目标：
   `build`（Maven 打包）、`images`（打镜像）、`up` / `down`、`status`、`logs`、`wait`
2. 把 Day 2 的 11 条 `docker build` 固化成 `script/docker/build-images.sh`
3. `Makefile` 中预置三层叠加的 compose 文件列表，**避免手敲漏 `-f`**：
   ```make
   COMPOSE_FILES = -f script/docker/docker-compose.yml \
                   -f script/docker/docker-compose.health.yml \
                   -f script/docker/docker-compose.bridge.yml
   ```

**为什么**：叠加层**不会自动生效**——直接 `docker compose up -d` 不报错，但也不加载。
这个坑文档里已经记过一次，把它固化进 Makefile 是最彻底的防呆。

**验收标准**：`make build`、`make images` 可执行；`make status` 输出各服务状态。

---

### Day 11 · 10/28（三）— 镜像标签规范与配置外置

**目标**：让制品**可追溯**，让镜像**不携带环境信息**。

**做什么**

| 项 | 改造内容 | 对应 DevOps 能力 |
|---|---|---|
| 镜像标签 | 从固定 `6.0.0` 改为 `${VERSION}-${GIT_SHA}`，同时保留 `latest` | 制品可追溯、可回滚 |
| 配置外置 | MySQL / Redis 口令等敏感信息改用 `.env` 或 Secret 注入，**不进镜像** | 安全与多环境复用 |
| 构建产物归档 | jar 与镜像清单输出到 `artifacts/` | 制品管理 |

**为什么**：固定标签 `6.0.0` 意味着"每次构建产物都叫同一个名字"——
出问题后你无法回答"线上跑的是哪次提交"。这是上平台前必须解决的。

**验收标准**：`docker images` 中镜像带 commit sha；镜像内不含明文口令。

---

### Day 12 · 10/29（四）— CI 流水线脚本

**目标**：把"人肉执行的一串步骤"变成**一条可重复执行的命令**。

**做什么**

编写流水线脚本，串联完整链路：

```
构建 jar → 打镜像 → 启依赖(mysql/redis/nacos) → 等待就绪 → 导入配置 → 启业务 → 健康检查 → 端到端冒烟
```

`[建议]` 先用 shell 脚本实现（无平台依赖）。后续移植到 Jenkins / GitLab CI 时，
只需把每一步换成平台的 `script:` 块即可。

**为什么**：这是"为 DevOps 平台做准备"的**直接交付物**。
平台只是调度器，真正的价值在于这条链路本身已被验证过、且可重复。

**验收标准**：干净环境执行一次脚本能跑到浏览器可访问；失败时有明确退出码与日志。

**失败怎么办**：先确保每一步单独执行都成功，再串联。脚本要**每步打印耗时**，
便于定位卡在哪一环。

---

### Day 13 · 10/30（五）— 收尾与沉淀

- 更新 `project-progress.md` 的阶段 B/C/D 清单
- 更新 `docs/README.md`（**修正 1.2 中的两处过时结论**）
- 补 ADR：记录"host → bridge 迁移"这一架构决策（按 `development-standards` §13 格式）
- 提交全部未入库资产（当前 `bootstrap-data.sh`、`.env`、叠加层等均为未跟踪状态）
- 回顾：对照第〇章的两个 P0 阻塞，确认均已解除

---

## 四、按月历排期（2026 年 10 月）

### 4.1 节假日与工作日核定

> 依据：**《国务院办公厅关于 2026 年部分节假日安排的通知》**（国办发明电，2025-11-04 发布）
> 来源：[中国政府网](https://www.gov.cn/govweb/yaowen/liebiao/202511/content_7047099.htm)

| 类别 | 日期 | 是否已过 |
|---|---|---|
| 国庆节放假 | **10/1（四）– 10/7（三）**，共 7 天 | 已过 |
| 调休上班 | 9/20（日）、**10/10（六）** | 已过 |
| 中秋节放假 | 9/25（五）– 9/27（日） | 已过 |

**结论**：10/13（今日）之后，10 月内**不再有法定节假日或调休上班日**，
需要排除的只剩**周末**。若你所在单位另有安排，按实际情况调整即可。

### 4.2 工作日排期表

10/13 – 10/31 共 **14 个工作日**（排除 10/17–18、10/24–25、10/31 三个周末）。

| 日期 | 星期 | 任务 | 阶段 | 核心交付物 | 硬验收标准 |
|---|---|---|---|---|---|
| **10/13** | 二 | **Day 0** 计划 + 环境准备 | 准备 | 代码迁至 WSL ext4 | `~/workspace/RuoYi-Cloud-Plus` 可构建 |
| **10/14** | 三 | **Day 1** Maven 构建验证 ⚠️ | 一 | 全部业务 jar | `target/*.jar` ≥ 11 个 |
| **10/15** | 四 | **Day 2** 构建 12 个镜像 ⚠️ | 一 | 11 个 `ruoyi/ruoyi-*:6.0.0` | `docker images` 计数 = 11 |
| **10/16** | 五 | **Day 3** Nacos 配置导入 | 二 | 配置中心就绪 | dataId 与源文件一一对应 |
| 10/17 | 六 | — 周末 — | | | |
| 10/18 | 日 | — 周末 — | | | |
| **10/19** | 一 | **Day 4** host 下注册验证 | 二 | 服务注册成功 | Nacos 中可见健康实例 |
| **10/20** | 二 | **Day 5** bridge 迁移 ⭐ | 三 | 浏览器可访问 | `localhost:8848` → 200 |
| **10/21** | 三 | **Day 6** 前端构建部署 | 三 | dist 挂载到 nginx | `localhost` 返回登录页 |
| **10/22** | 四 | **Day 7** 端到端验证 | 三 | 可登录可用 | 登录成功 + 数据加载 |
| **10/23** | 五 | **Day 8** 健康检查 + 冷启动 | 四 | 冷启动可复现 | readiness 退出码 0 |
| 10/24 | 六 | — 周末 — | | | |
| 10/25 | 日 | — 周末 — | | | |
| **10/26** | 一 | **Day 9** 故障注入与恢复 | 四 | 自愈能力验证 | 停库后自动恢复 |
| **10/27** | 二 | **Day 10** Makefile + 构建脚本 | 五 | 统一命令入口 | `make build` 可用 |
| **10/28** | 三 | **Day 11** 镜像标签 + 配置外置 | 五 | 制品可追溯 | 镜像带 commit sha |
| **10/29** | 四 | **Day 12** CI 流水线脚本 | 五 | 一键串联 | 脚本可重复执行 |
| **10/30** | 五 | **Day 13** 收尾：文档 + ADR + 提交 | 收尾 | 工作区干净 | `git status` 无遗漏 |
| 10/31 | 六 | — 周末 — | | | |

> ⚠️ 标记的两天（10/14、10/15）是**串行硬依赖且风险最高**的两天——无 jar 则无镜像，
> 且 Maven 目前处于失败状态。**这两天是整个计划的关键路径，建议预留整块时间。**

### 4.3 排期取舍：延误时先砍哪里

14 个工作日刚好排满 13 个任务日，**没有冗余缓冲**。若发生延误，按以下优先级压缩：

| 优先级 | 阶段 | 能否压缩 | 理由 |
|---|---|---|---|
| **最高（不可砍）** | 阶段一（Day 1–2 制品） | ❌ 不可 | 后续一切的前置，砍了等于计划作废 |
| **高（尽量保）** | 阶段二、三（Day 3–7 跑起来） | ⚠️ 可延不可砍 | 这是"在 WSL 上跑起来"这个**首要目标**本身 |
| **中（可压缩）** | 阶段四（Day 8–9 可恢复性） | ✅ 可合并为 1 天 | 先做冷启动验证，故障注入可延后 |
| **低（可延到下月）** | 阶段五（Day 10–12 DevOps） | ✅ 可整段顺延 | 服务于"为 DevOps 做准备"，**不影响本月跑起来的目标** |

`[建议]` 若 10/23 前进度落后 ≥ 2 天，直接把阶段五（10/27–29）顺延到 11 月初，
把腾出的时间补给阶段二、三。理由：本月的核心 KPI 是"跑起来"，DevOps 准备工作是加分项而非验收项。

> **阶段内耦合提醒**：Day 3（配置导入）与 Day 5（bridge）存在耦合——
> 配置导入若走 Nacos 控制台，需要先有 bridge 才能让浏览器访问。
> 因此 Day 3 必须用 **API 或直写 MySQL `config_info` 表**的方式，避免被网络问题卡住。

---

## 五、每日工作结果记录

### 5.1 怎么记（两种方式）

**方式一：脚本生成（推荐）**

```bash
# [WSL-Ubuntu] 或 [Git Bash]，在仓库根目录执行
bash script/daily/new-day.sh              # 用今天
bash script/daily/new-day.sh 2026-10-14   # 或指定日期
```

脚本会做四件事：从 `docs/daily/TEMPLATE.md` 生成 `docs/daily/YYYY-MM-DD.md`、
自动填入日期与星期、查排期表填入 Day 编号与任务名、
**目标文件已存在时拒绝覆盖**（防止误删当天记录）。

**方式二：手工复制**

```bash
cp docs/daily/TEMPLATE.md docs/daily/2026-10-14.md
```
然后把文件里的 `{{DATE}}`、`{{WEEKDAY}}`、`{{DAY_NUM}}`、`{{DAY_TASK}}` 四个占位符替换掉。

### 5.2 记录原则

每天收工前填写，**控制在 5–10 分钟**。三个必填项：

1. **实际做了什么**——贴命令与输出原文，不写"执行成功"这种无证据的结论
2. **与计划的偏差**——无偏差就写"无"。偏差本身不是问题，**不记录偏差才是**，
   它是后续排期调整的唯一依据
3. **明天的第一件事**——只写一件，且必须是一条能直接复制执行的命令

### 5.3 汇总表

| 日期 | 星期 | 计划任务 | 实际结果 | 偏差原因 | 明日首要任务 | 状态 |
|---|---|---|---|---|---|---|
| 10-13 | 二 | Day 0 计划 + 环境准备 | 计划已产出；现状盘点完成；定位 2 个 P0 | — | 代码迁至 WSL + 验证构建 | 进行中 |
| 10-14 | 三 | Day 1 Maven 构建 | | | | ⬜ |
| 10-15 | 四 | Day 2 构建镜像 | | | | ⬜ |
| 10-16 | 五 | Day 3 Nacos 配置导入 | | | | ⬜ |
| 10-19 | 一 | Day 4 host 下注册验证 | | | | ⬜ |
| 10-20 | 二 | Day 5 bridge 迁移 ⭐ | | | | ⬜ |
| 10-21 | 三 | Day 6 前端构建部署 | | | | ⬜ |
| 10-22 | 四 | Day 7 端到端验证 ⭐ | | | | ⬜ |
| 10-23 | 五 | Day 8 健康检查 + 冷启动 | | | | ⬜ |
| 10-26 | 一 | Day 9 故障注入与恢复 | | | | ⬜ |
| 10-27 | 二 | Day 10 Makefile + 脚本 | | | | ⬜ |
| 10-28 | 三 | Day 11 镜像标签 + 配置外置 | | | | ⬜ |
| 10-29 | 四 | Day 12 CI 流水线 | | | | ⬜ |
| 10-30 | 五 | Day 13 收尾 + ADR + 提交 | | | | ⬜ |

> 状态图例：`✅ 完成` · `进行中` · `⚠️ 有偏差` · `⬜ 未开始`

---

## 六、原则与边界

沿用 `development-standards_2026_10_10.md`：

1. **overlay 优先**——不改上游 `docker-compose.yml`，新增叠加层。
2. **可逆性**——每步改动都能 `git checkout` 回去。
3. **验证驱动**——每一步都要有可执行的验收命令和预期输出，不接受"应该没问题"。
4. **区分事实与推断**——未实测的结论必须标注 `[推断]` 并附依据。
5. **提交由你本人执行**——我只准备变更说明。

## 七、遗留待确认

**技术层面**

- [ ] `plus-ui` 前端仓库是否已有本地副本（影响 **10/21**）
- [ ] Nacos v3.2.3 配置导入的**可用 API 端点与鉴权方式**（**10/16** 前置）
- [ ] 全量 30 个服务是否都需要启动，还是只跑核心链路（gateway + auth + system + 前端）

**排期层面**

- [ ] 所在单位 10 月是否另有调休/年假安排（本计划按国务院通知，
      10/13 之后无调休处理；若有变化需重排 4.2 表）
- [ ] 10/14–10/15 能否预留整块时间（这两天是串行关键路径，
      首次 Maven 全量构建预计 20–60 分钟，中断需重来）
