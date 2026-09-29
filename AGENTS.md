# AGENTS.md

## 项目说明

- 本项目是 PositionAssistant（持仓助手），包含 Node.js/Express 后端、Web 原型和 Flutter 客户端。
- 后端入口为 `server/index.js`，默认监听 `http://localhost:3000`。
- PostgreSQL 迁移文件位于 `server/db/migrations/`；原型业务仍有部分使用 `data/db.json`。
- Flutter 客户端位于 `client/`，客户端专用命令应在该目录执行。
- 本地自带独立构建与打包工具链（详见下文“开发命令”），配套专属项目级 skill 位于 `.agents/skills/build-position-assistant-apk/`。
- 详细开发和功能验收说明见 `docs/development.md`；交接信息见 `docs/agent-handoff.md`。

## 用户指令

- 当用户要求添加任何新的 skills 时，默认将 skills 下载到 `%USERPROFILE%/.agents/skills` 文件夹下，然后分别在 `%USERPROFILE%/.claude/skills` 和 `%USERPROFILE%/.codex/skills` 中使用 `mklink /D` 创建目录软链接。

## 子代理使用

子代理在我们的工作里用于探索，他是你的探子。把子代理当成你手边最顺手的、用于「宽而重」读取的工具。工作的任何时候，只要你觉得需要就可以派。只有在它能减少主线程上下文污染、提高并行度或者提供独立核验的时候才使用。

必须遵守：你需要在任何需要的情况下调用子代理，而不仅仅只是在对话的开头。我们需要更聪明的子代理调用来避免上下文腐烂，你承担子代理编排者的角色。

### 何时直接处理

直接读取以及处理以下内容，不派子代理：

* 已知位置的小文件、少量代码或者单一事实；
* 即将修改的具体代码；
* 派发、等待以及复核的成本不低于自己读取的任务；
* 奠基性文档，无论多长都自己读：架构文档、设计文档、交接备忘录（在别的工作流里可能是别的名字）等用来让你建立全局视角、充当后续判断地基的文件——它们的价值全在细节与脉络，一经子代理转译即失真，长度不构成外包的理由。

### 何时适合派发

适合交给子代理的：

* 巨型大文件（奠基性文档除外，见「何时直接处理」）、跨文件或者跨目录的检索；
* 相互独立、可以并行的探索或者核验；
* 长任务当中需要重新确认模块现状的；
* 会产生大量日志、搜索结果或者外围材料的阅读。

多个独立的任务应当并发派发。

### 委派与验证

给子代理的任务必须是自包含的，说明检索范围、具体问题以及期望的输出。精度重要的时候，要求返回 `file:line`、符号名以及必要的关键原文——这些出处就是你之后廉价复核的抓手。

子代理的结果只是线索，可能遗漏或者出错。但复核不是把它读过的东西重读一遍，那样这次派发就白费了——你买的是「压缩」，重读会把压缩当场退光。复核 = 顺着它给的 `file:line` 以及关键原文来。抽查真的需要主代理亲自阅读的那几小部分，别去重新通读整份材料；既然把「读」外包了出去，就靠它压缩之后的结论来干活，只在结论要紧或者可疑的时候回去点验出处。

唯二需要你亲自完整读原文的是：① 即将修改的确切代码，② 奠基性文档——这两类本就不外包（见「何时直接处理」）。对它们，子代理至多帮你定位，读由你亲自来：定位与阅读是分工，并非重复劳动。

子代理只做探索、检索以及核验。代码修改、方案取舍以及最终验证由主代理负责。

### 派发机制

* 是否派、派几个由你自主决定，无需用户明确要求；较重的探索应当拆成多个独立的轻任务来并发派发。
* 最多并行 10 个子代理。10 是天花板，不是派发目标：只你按照实机情况自行决定派发多少，我们更倾向更多并行的子代理，单个子代理给轻且集中的任务。
* 派生时除必须显式传入的 `fork_turns`（见下条）外，省略其余全部可选参数：不传 `agent_type`、`model`、`reasoning_effort`、`service_tier`，由泛型派生加载 `default.toml`。禁止选用 `worker`、`explorer` 或者其他角色。
* 派生时必须显式 `fork_turns = "none"`，不复制主代理的历史，让每个探子都保持干净、快、不背主代理正在腐烂的上下文。
* 每个子代理只用一轮：不复用、不追派、不用 `followup_task`；需要更多信息时，重派一个干净的新子代理。

### 等待与介入

* 派发后立即进入 `wait_agent`。只要仍有会影响当前任务的子代理在运行，就继续等待，不自行推进其他工作，也不接管已经委派的检索范围。委派意味着这部分探索已经交出去：主代理此时的职责从「继续干活」切换为「编排、等待、收敛」。
* 每次 `wait_agent` 返回只代表发生了一个事件，可能是子代理交卷，也可能只是超时。醒来后消费已返回的终态结果、检查仍在运行的子代理并更新名单；仍需等待就再次 `wait_agent`。以信封里的 Sender（代理路径）识别子代理，不用 Task name。
* `MESSAGE` 只视为过程信号；只有 `FINAL_ANSWER` 或 completed 状态才算终态。子代理在途期间不要修改其检索范围内的文件；涉及全仓检索、否定结论或跨目录关系时冻结整个工作区修改。
* 子代理明显滞后时，可用 `send_message` 催收一次，要求停止扩展范围并尽快以 partial 状态返回已核实内容。催收后仍无终态则 `interrupt_agent`；缺口仍重要时缩小范围重派，不原样重试。
* `send_message` 只用于催收或收紧，不用于追加问题、改变任务范围或来回追问；需要实质改变任务时，中断后重派。

## 本地文件检查

优先使用 FastCtx MCP 服务自己的 `inspect_local_file`、`grep` 和 `glob` 工具读取、搜索和查找本地文件。若 FastCtx 不可用，再使用 `rg` 等命令行工具。

读取多个文件时，优先在一次 `inspect_local_file` 调用中传入多个文件。结果最后一行会标明 `Complete` 或 `Partial`；出现 `Partial` 时只按结果提供的精确参数继续读取。

机械性的跨文件查找替换优先使用 FastCtx 的 `replace`，以保留编码和换行符；生成内容、语义重写或小范围编辑使用 `apply_patch`。

Shell 命令必须非交互式。长任务使用后台任务、查询输出并在必要时停止；不要在命令中复用 `$HOME`、`$home` 或 `$CODEX_HOME` 作为自定义变量。命令文本按代码处理，避免未转义的反引号、`$()` 和敏感信息泄露。

## 开发命令

在项目根目录执行：

```bash
npm ci
npm start
npm run db:migrate
npm run test:migrations
npm run test:catalog
npm run test:nav
npm run test:market
```

运行数据库相关命令前，按 `docs/development.md` 配置 `.env` 并启动 PostgreSQL。不要提交 `.env`、密码或生产数据库连接信息；不要通过删除数据库卷来解决有价值数据的连接问题。

常用 Node.js 检查：

```bash
node --check server/index.js
node --check server/<changed-file>.js
```

### Flutter 客户端与 Android 工具链

由于系统 PATH 未配置全局 Flutter，本项目使用根目录下自带的独立工具链：
- Flutter SDK：`.tooling/flutter/bin/flutter.bat`（Flutter 3.47.4 stable）
- Android SDK：`C:\lib`（配置见 `client/android/local.properties`）

在 `client/` 目录执行静态分析与测试：

```bash
..\.tooling\flutter\bin\flutter.bat analyze
..\.tooling\flutter\bin\flutter.bat test
```

### Android APK 打包与产物交付

项目提供一键打包脚本与配套项目级 Skill（`.agents/skills/build-position-assistant-apk/`），禁止用 `flutter clean` 破坏 Gradle 增量缓存，产物统一自动重命名为 `持仓助手.apk` 并移至输出目录，不保留重复的 `app-release.apk`：

在项目根目录执行：

```cmd
scripts\build-apk.bat        # release 构建（默认），产物为 client\build\app\outputs\flutter-apk\持仓助手.apk
scripts\build-apk.bat debug  # debug 构建
```

## 修改约定

- 修改迁移时只能新增四位递增编号的 SQL 文件；已经执行的迁移不可修改、删除、重命名或插入旧编号。
- 上游基金、净值、行情和汇率数据通过可替换适配器接入；修改协议或解析规则时使用新的适配器标识，并保留缓存来源信息。
- 本地模式的正式净值由 `client/lib/data/nav_repository.dart` 直接请求东方财富历史净值接口并写入 SQLite 的 `navSnapshots` 集合；不得改回依赖持仓助手服务端。分页读取历史记录，按交易日期和截止时间选择首个不早于起点的净值；请求失败时交易必须保持待确认。
- 用户数据必须保持账号隔离；新增接口应覆盖未登录、越权、重复请求和数据源失败等边界情况。
- 修改后运行与改动直接相关的测试和 `node --check`；涉及 Flutter 客户端时运行 `flutter analyze` 和相关 `flutter test`。
- 不要回退或覆盖用户已有的未提交修改；发现无法解释的外部改动时先停止并询问用户。

## HTML 文件

当用户要求生成或修改 HTML 时，默认把 HTML 写入本地工作区并提供本地文件链接；除非用户明确要求在线网站或部署，否则不要返回 ChatGPT 域名网站。

## 输出要求

- 先说明结果，再说明关键改动、验证方式和仍存在的限制。
- 文件路径使用可点击的绝对路径链接或反引号包裹的路径；不要粘贴大段生成文件内容。
- 只有在确有帮助时使用标题和列表，保持说明简洁、直接、可核验。
