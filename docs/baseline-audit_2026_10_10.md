# 基线复验记录（BASE-01 / BASE-02）

> 复验时间：2026-10-10 16:40 (GMT+8)
> 执行环境：Git Bash on Windows（仓库 root 视角）
> 复验对象：`docs/project-progress_2026_10_10.md` 中所有标注「待复验」的条目
> 原则：本文件只记录**本次实际执行验证**的结果；未执行验证的项仍标注「待复验」。

## 1. BASE-01 仓库路径歧义 —— 已澄清，但结论与文档假设不同

文档 §2.2 假设存在两个路径、不能确认是否同一工作树。实际验证结论：**它们是两份独立的 Git 仓库**。

| 编号 | 路径 | root 确认 | 分支 | HEAD | origin |
|---|---|---|---|---|---|
| A | `D:\dev\project\RuoYi-Cloud-Plus` | `git rev-parse --show-toplevel` 通过 | `docs/project-progress` | `38d96ffd9` | `bvh-gif/RuoYi-Cloud-Plus`（个人 Fork） |
| B | `D:\dev\agent\RuoYi\RuoYi-Cloud-Plus` | `git rev-parse --show-toplevel` 通过 | `6.X` | `5e98cef44` | `dromara/RuoYi-Cloud-Plus`（**官方上游**） |

- `/mnt/d/dev/agent/...` 在 Git Bash 下不可访问（Git Bash 使用 `/d/` 挂载前缀），**不代表 WSL 内不存在**，需在 WSL 内部再确认一次。
- 提交关系：`git merge-base --is-ancestor 5e98cef44 HEAD` 在 A 中执行返回真 → **B 是 A 的祖先，同一条提交线**。
- 时间差：B 的 HEAD 为 2026-08-21，A 的 HEAD 为 2026-10-09 → **B 落后上游约 7 周**。
- 前端独立仓库：`D:\dev\agent\RuoYi\plus-ui`，origin `CrazyLionCat/plus-ui`，分支 `6.X-Vue`，工作区干净。

**状态：已完成（BASE-01）。**

## 2. BASE-02 Git 基线 —— 已记录，但发现版本不一致

| 项目 | 本次实测 | 文档记载 | 差异 |
|---|---|---|---|
| Git 版本（Git Bash） | `2.55.0.windows.3` | `2.53.0.windows.2` | ⚠️ 不同命令使用了不同的 Git 安装实例，需统一记录两处路径 |
| 是否浅克隆 | `false` | 同 | ✅ |
| 提交总数（A） | 3898 | 3897（未含 docs 提交） | ✅ 一致（新增 `38d96ffd9`） |
| `origin` fetch 规则 | 仅 `6.X` + `docs/project-progress` 两条 refspec | 同 | ⚠️ 仍不是 `*`，`git fetch` 拉不到其它远程分支 |
| 提交身份 | `bvh-gif <71245564+bvh-gif@users.noreply.github.com>` | 未记录 | ✅ 已配置（此前未配置） |
| A 工作区 | `?? docs/development-standards_2026_10_10.md`、`?? docs/project-progress_2026_10_10.md` | 未记录 | ⚠️ 两份规范文档**尚未入库** |

**状态：部分完成。剩余动作已转为 BASE-03。**

## 3. 复验中发现的三个新问题（文档未覆盖，建议按 P0 处理）

### 3.1 B 副本的 `origin` 直接指向官方上游 —— 违反 §2.1 约定

`D:\dev\agent\RuoYi\RuoYi-Cloud-Plus` 的 `origin = https://github.com/dromara/RuoYi-Cloud-Plus.git`。
在该目录执行任何 `git push` / `git push --force` 都是向官方仓库推送，而开发规范 §2.1 明确禁止。
**这属于配置层的高危项，不是代码问题，改一行 remote 即可消除。**

### 3.2 B 副本承载了全部未入库的工程化成果

已修改但未提交（6 个文件，116 增 / 223 删）：

```
 pom.xml                                     |  47 +++
 script/config/nacos/application-common.yml  |  28 +-
 script/config/nacos/seata-server.properties |  23 +-
 script/docker/docker-compose.yml            |  51 +-
 script/docker/redis/conf/redis.conf         |   1 +
 script/docker/seata/conf/application.yml    | 189 ---
```

未跟踪文件（19 项，其中含实际成果）：

```
.envrc                                   ← 极可能含凭据，必须先确认后决定是否忽略
script/docker/Makefile                   ← 文档 §5.1 提到的 `make dev` 只存在于此
script/docker/docker-compose-bridge.yml  ← bridge 网络替代方案
script/docker/Dockerfile.seata
script/docker/mysql-schema.sql  /  mysql-schema-from-image.sql  /  nacos-mysql.sql  /  seata-mysql.sql
script/docker/nacos_backup_20260831.sql
script/docker/nacos/data  logs           ← 容器运行时数据落在工作树内
script/docker/redis/data/                ← 含 dump.rdb
script/docker/seata/libs  logs
script/config/nacos/nacos.zip
re.md
```

**风险**：这些成果没有任何提交记录保护；且在同一棵工作树里 `git add -A` 会一并卷入 `.envrc` 与容器 runtime 数据。
**注意：`seata/conf/application.yml` 被删除了 189 行**，删除是否有意需要确认。

### 3.3 docker-compose.yml 大量使用 `privileged: true` + `network_mode: "host"`

`script/docker/docker-compose.yml` 共 28 个 service，其中至少 8 个同时带这两项（行 24-25、65-66、99-100、116-117、137-138、153-154、167-168、187-188…）。
开发规范 §6.3 要求「每项都需有明确理由和最小权限边界」——目前**没有任何文档记录这些理由**，与 SEC-01 直接冲突。

## 4. 对前一份 Git 初始化脚本的修正

`D:\dev\project\ruoyi-git-setup.sh` 第 3 步原先假设「origin 指向他人 fork」——**该假设错误**：`bvh-gif` 就是你自己的 Fork。
已修正为：若 `origin` 已等于 Fork URL 则保持不动。请以本文件结论为准，**不要手工把 origin 改名出去**。

## 5. 建议的下一步（按 P0 排序）

| 序号 | 动作 | 目的 |
|---|---|---|
| 1 | B 副本 `git remote set-url origin https://github.com/bvh-gif/RuoYi-Cloud-Plus.git` | 消除误推官方的风险（先做，零成本） |
| 2 | A 副本提交两份规范文档到 `docs/project-progress` 分支 | 已完成的工作要进版本库 |
| 3 | 给 A 的 origin 补通配 fetch refspec（`git remote set-branches origin '*'`），或明确约定只同步两个分支 | 消除 fetch 盲区 |
| 4 | 盘点 `.envrc` 是否含真实凭据 → 是则加入 `.gitignore`（或用 `.git/info/exclude`） | 凭据不入库 |
| 5 | 决定 B 的成果如何迁入 A：复制文件 + 手工重做改动 vs `git format-patch` 迁移 | 统一到单一工作树，消灭路径歧义 |
| 6 | 为 `privileged` / `network_mode: host` 逐项记录理由，或改用 `docker-compose-bridge.yml` | SEC-01 |
