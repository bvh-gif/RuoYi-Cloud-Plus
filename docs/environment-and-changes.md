# 环境说明与改造记录

> 本文回答两个问题：**这套环境是在什么上面跑的**、**我们对这个项目做了哪些改造**。
> 原则：只记录实际执行并验证过的命令与结果。未核实的部分明确标注「未核实」。
>
> 最后更新：2026-10-18

---

## 一、运行环境

### 硬件与操作系统

| 项 | 值 | 来源 |
|---|---|---|
| 主机 | DESKTOP-VJS5F8A | 用户环境 |
| 操作系统 | Windows 11 | 用户环境（具体 build 号未核实：`cmd /c ver` 在本沙箱被拦截） |
| CPU | Intel Meteor Lake 系列 SoC，集成显卡 + Intel NPU（AI Boost） | 用户环境 |
| Docker 内存上限 | **15.35 GiB** | `docker stats` 实测 |
| 虚拟化 | WSL2 | `docker info` → Kernel `6.6.87.2-microsoft-standard-WSL2` |

> WSL 发行版列表与 `wsl --version` **未核实**——`wsl.exe` 在本执行沙箱中被安全策略拦截。
> 内核串中的 `microsoft-standard-WSL2` 可以确认是 WSL2 而非 WSL1，也非 Hyper-V 传统模式。

### 工具链

| 项 | 版本 | 备注 |
|---|---|---|
| Docker Desktop | **29.3.1** | `docker version --format '{{.Server.Version}}'` |
| Maven（项目 wrapper） | **3.9.12** | 由 `.mvn/wrapper/maven-wrapper.properties` 锁定 |
| Maven（系统 scoop） | 3.9.14 | **不推荐使用**，历史配置指向另一个 local repo |
| JDK（构建） | 21 | `pom.xml` `<java.version>21` |
| JDK（容器内） | 21.0.12.1（BellSoft Liberica） | 基础镜像 `bellsoft/liberica-openjdk-rocky:21.0.12-cds` |

### 中间件容器

| 项 | 镜像 | 版本 | 关键配置 |
|---|---|---|---|
| MySQL | `mysql:8.4.9` | 8.4.9 | root 密码 `ruoyi123`；`utf8mb4_general_ci` |
| Redis | `redis:8.6.3` | 8.6.3 | `requirepass ruoyi123` |
| Nacos | `nacos/nacos-server:v3.2.3` | **3.2.3** | 主端口 8848，**控制台端口 18080** |
| Seata | `apache/seata-server:2.6.0` | 2.6.0 | **未启用**（`seata.enabled: false`） |

### 项目版本

| 项 | 值 |
|---|---|
| `${revision}` | **6.0.0** |
| Spring Boot | 4.1.1 |
| Spring Cloud | 2025.1.2 |
| MyBatis-Plus | 3.5.17 |
| Sa-Token | 1.46.0 |
| Redisson | 4.7.0 |
| dynamic-datasource | 4.5.0 |
| warm-flow（工作流） | 1.8.9 |
| LiteFlow | 2.16.2.1 |

---

## 二、架构要点

### 双服务发现

- **Spring Cloud**：网关通过 `lb://` + Nacos 做路由，注册在 `DEFAULT_GROUP`
- **Dubbo**：服务间调用走 `@DubboService` / `@DubboReference`，注册在 `DUBBO_GROUP`
- **无 Feign**
- 两者共用同一个 Nacos

### 配置中心驱动

数据库连接、Redis 地址、路由规则**全在 Nacos 里**。服务声明 `optional:nacos:...`，
配置缺失时**静默跳过、不报错**——所以"配置没导入"不会有任何显性症状，
只表现为"服务起来了但行为和预期不一致"。

### 网络模式

`docker-compose.yml` 中 28 个 service 全部 `network_mode: "host"`。

**关键事实**：host 网络下的"宿主机"是 Docker Desktop 的隐藏发行版 `docker-desktop`
（IP 段 192.168.65.x）的网络命名空间，**不是 Windows、也不是 WSL Ubuntu 发行版**。
三者的 `127.0.0.1` 互不共享。实测：

```
容器内   curl 127.0.0.1:8848     → 200  ✅
Windows  localhost:8848          → 10061（拒绝连接）
Windows  192.168.65.3:8848       → 000
```

推论：**浏览器与 WSL 均无法访问任何服务**，端到端验证只能"进另一个容器里 curl"，
真正的端到端必须迁移到 bridge 网络（尚未实施）。

另外，host 模式下 `ports:` 映射**被丢弃**，compose 会打印：
```
Published ports are discarded when using host network mode
```

---

## 三、改造工作清单

### 1. Maven 环境治理（10-13）

**问题**：两套 toolchain（项目 `mvnw` 3.9.12 / 系统 `mvn` 3.9.14）指向不同的 `localRepository`
——`~/.m2/repository`（正确）与 `D:\dev\repo\maven-repo`（缺 3 个 BOM）。
误用系统 mvn 会导致构建直接失败。

**改造**：
- 新增用户级 `~/.m2/settings.xml`：统一 `localRepository` + 华为云 `mirrorOf=central` 镜像
- 新增根目录 `Makefile`（`online` / `offline` / `verify` + Docker 组）与等价的 `script/build.sh`
  ——Windows 侧没有 `make`，`build.sh` 是给 Windows 用的入口
- 约定：**只用 `./mvnw`**

**验证**：`./mvnw -o clean install -DskipTests` 离线通过，证明依赖缓存自足。

### 2. Git 卫生（10-13）

- `.gitignore` 追加 4 类：`.local-data/`（219MB 运行时数据）、`.workbuddy/`、`docs/daily/`、`*.bak`
- `.gitattributes` 扩展：`*.sh` / `Makefile` / `*.yml` / `*.yaml` / `*.env` 全部 `text eol=lf`
  ——仓库 `core.autocrlf=true`，否则 WSL 下 `script/*.sh` 会报 `bad interpreter: /bin/bash^M`
- 统一 **Conventional Commits v1.0.0** 提交规范

### 3. 业务镜像（10-15）

- **修复 P0**：`ruoyi-gateway/Dockerfile` 引用 `ruoyi-gateway-mvc.jar`，
  但该模块 pom 未设 `finalName`，实际产物是 `ruoyi-gateway.jar` → `docker build` 必然失败。
  已对齐其余模块的写法。
- 新增 `script/build-images.sh`：11 个模块的「目录 → 镜像名」映射，镜像名与 compose 声明严格一致
- **11 个镜像全部构建成功，失败数 0**（计划文档写的"12 个"有误，compose 实际声明 11 个）

### 4. 数据库（10-16）

**发现**：`datasource.yml` 期望 **4 个库**，而 MySQL 里只有 `ry-cloud` 且 **0 张表**，
另外 3 个库根本不存在。计划文档 Day 1–11 **完全没有这一步**。

| 库 | 表数 | 源脚本 |
|---|---|---|
| ry-cloud | 25 | `script/sql/ry-cloud.sql` |
| ry-job | 23 | `script/sql/ry-job.sql` |
| ry-ai | 23 | `script/sql/ry-ai.sql` |
| ry-workflow | 12 | `script/sql/ry-workflow.sql` |

> 排障记录：查中文必须带 `--default-character-set=utf8mb4`，否则客户端默认 latin1
> 会把 `疯狂的狮子Li` 显示成 `?????Li`。**这是客户端问题，数据一直是好的。**

### 5. Nacos 3.x 适配（10-16）

v3 与 v2 差异极大，全部实测确认：

| 项 | v2 做法 | v3 实际 |
|---|---|---|
| 配置读写 | `/nacos/v1/cs/configs` | **已移除**（GET 和 POST 都 404），须用 `/nacos/v3/admin/cs/config` |
| 鉴权 | 可选 | query 参数 `accessToken=<token>` |
| 分组参数名 | `group` | **`groupName`** |
| 控制台端口 | 8848 | **18080**（v3 端口拆分） |
| 管理员账号 | 内置 `nacos/nacos` | **自 2.4.0 起不再内置**，须一次性 bootstrap |

新增 `script/nacos-config-import.sh`（支持 `--check`），导入 **14 条**：
13 个 yml → `DEFAULT_GROUP`，`seata-server.properties` → `SEATA_GROUP`。

管理员凭据：**`nacos` / `ruoyi123`**（`POST /nacos/v3/auth/user/admin`，一次性不可逆）。

### 6. 内存治理（10-17）

**问题**：业务 Dockerfile 里 `ENV JAVA_OPTS=""` 是空的，JVM 默认最大堆 = 可见物理内存的 1/4
（本机约 3.8GB）。11 个服务全起吃到 **10.6GB**，总计 12.1GB → **Nacos 被 OOM 重启**，
Docker 守护进程间歇性返回 HTTP 500。

**改造**：
- 新增 `script/docker/docker-compose.mem.yml`：注入 `JAVA_OPTS=-Xms… -Xmx… -XX:MaxMetaspaceSize=256m`
  ，两个变量可调：`RUOYI_JVM_XMX`（默认 768m）/ `RUOYI_JVM_XMX_HEAVY`（默认 1g）
- 新增 `script/stack.sh` 三档入口（见下）

### 7. 三档堆栈入口（10-17）

| 档位 | 命令 | 常驻 | 堆上限 | 内存 | 场景 |
|---|---|---|---|---|---|
| minimal | `stack.sh minimal up` | 3 个核心 | 512m/640m | ~4.4GB | 日常开发联调 |
| verify-all | `stack.sh verify-all` | 滚动，一次只多 1 个 | 448m/640m | **峰值 ~2.8GB** | 验全部模块代码 |
| full | `stack.sh full up` | 11 个 | 768m/1g | ~12GB | 正常使用（需 Docker 内存 ≥16GB） |

`verify-all` 的关键认知：**内存成本取决于"同时有几个 JVM 在跑"，不是"一共验证几个"**。
滚动模式一次只多起一个、确认注册后立即停，峰值省一半以上，代价是串行约 4 分钟。

> 实测：堆上限 448m 下 8 个附加模块**全部能正常启动并完成注册**（4m14s，8 PASS / 0 FAIL），
> 说明 768m 的默认值偏保守。模块间依赖：`ruoyi-job → snailjob-server`、`ruoyi-ai → snailai-server`。

### 8. 验收脚本（10-17）

`script/verify-stack.sh` 五段式检查，退出码 = FAIL 项数，可接 CI：

1. 业务镜像 11 个
2. 4 个业务库表数 + 中文编码
3. Nacos 登录 + 14 条配置
4. 服务注册且 `healthy: true`
5. 容器内端到端调用

> 修掉过一个假阳性：原第 5 段只校验 `GET /code` 的 HTTP 状态码，但该接口 **HTTP 恒为 200**，
> 真实业务码在 body 里（未带 token 时是 `{"code":401,...}`）→ 检查永远 PASS。
> 已改为同时校验响应体结构。

### 9. 一键重建（10-18）

新增 `script/bootstrap.sh`，**幂等**，固化全部手工步骤：
起基础设施 → 建 4 库 → 导表（表数 > 0 则跳过）→ bootstrap Nacos 管理员（能登录则跳过）
→ 导配置 → 可选起最小集。

```bash
./script/bootstrap.sh                # 重建到「可起服务」状态
./script/bootstrap.sh --with-stack   # 顺便把最小集也起来
```

---

## 四、当前状态（2026-10-18）

| 项 | 状态 |
|---|---|
| 业务镜像 | ✅ 11 / 11 |
| 数据库 | ✅ 4 库 83 表，含初始数据 |
| Nacos 配置 | ✅ 14 条 |
| 服务注册 | ✅ minimal 档 3 个 healthy；滚动验证 11 个全过 |
| 内存 | ✅ 最小集约 4.9GB（原 12.1GB），Nacos 稳定不再被 OOM |
| 一键重建 | ✅ `script/bootstrap.sh`（脚本已写，待 Docker 恢复后实测） |

### 已知限制与待办

1. **Nacos 仍用嵌入式 Derby**，不是 MySQL（`nacos` 库 0 张表）→ 配置不可备份、无 SQL 兜底。
   建库脚本在 `docs/legacy/artifacts/sql/nacos-mysql.sql`（未执行）。建议与 bridge 迁移合并做。
2. **bridge 迁移未做**——host 网络下浏览器/WSL 一律够不着。
3. **仓库无前端目录**，目前只能做 API 级验证。
4. **无备份脚本**，MySQL 4 个库与 Nacos 配置均无备份。
5. **Nacos 登录噪音**：用户 `ruoyi` 缺 `ROLE_ADMIN`，客户端登录失败每秒刷 ERROR。
   不影响功能（注册走匿名成功，`nacos.core.auth.enabled=false`），但污染所有容器日志。
6. **真实登录端到端未跑通**——`/auth/login` 带 `@ApiEncrypt`，全局加密默认开启，
   明文请求会被 `CryptoFilter` 拒绝（返回 403 / `认证客户端id不能为空`），这是预期行为。
   要做明文登录测试须先关 `api-decrypt.enabled` 与 `security.captcha.enabled`。
7. **`full` 档当前物理上跑不了**：需要 ≥16GB，Docker 上限仅 15.35GiB。建议调到 24GB。

---

## 五、快速上手

```bash
# 1. 重建环境（幂等，可重复执行）
./script/bootstrap.sh --with-stack

# 2. 验收
./script/stack.sh minimal verify

# 3. 日常切换
./script/stack.sh minimal up          # 开发联调，~4.4GB
./script/stack.sh verify-all          # 验全部模块，峰值 ~2.8GB
./script/stack.sh full up             # 正常使用，~12GB（需先调 Docker 内存）

# 4. 只重新导配置（改了 script/config/nacos/ 之后）
./script/nacos-config-import.sh
```
