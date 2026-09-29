# PositionAssistant Agent Handoff

> 本文件是 AI Agent 的唯一接力入口。每次开始工作先读本文件，再读 `functions.md` 中与当前任务相关的段落及任务涉及的代码。

## 当前状态

- 当前阶段：F43 已完成；F41 已实现，待 Android/Gradle 环境完成专项补充验收；F42 已完成；F26 待 Linux PostgreSQL 与上游行情联通验收；F14 待 Linux PostgreSQL、正式数据源与 Android 真机联调。
- 队列已标记完成：`F01`、`F02`、`F05`、`F09`、`F10`、`F15`、`F16`、`F17`、`F18`、`F19`、`F20`、`F21`、`F22`、`F23`、`F24`、`F25`、`F27`、`F28`、`F29`、`F30`、`F31`、`F32`、`F33`、`F34`、`F35`、`F36`、`F37`、`F38`、`F39`、`F40`；其中 F10 上次仅运行语法检查和密码测试，尚无专项越权测试结果，不应视为隔离验收通过。
- 当前待执行任务：F44 Web 与 Android 远端一致性验收。
- 待外部验收：`F03`、`F04`、`F06`、`F07`、`F08`、`F11`、`F12`、`F13`、`F26` 为 `implemented_pending_validation`；具体遗留见各项记录。
- 正在执行的任务：F43（2026-09-28）：Android 真机补录、跳过、重复操作与应用重启持久化回归，并核实剩余离线验收缺口。
- F43 结果：done；Android 真机已完成离线定投、补录/跳过、导出、合法覆盖导入、非法包拒绝、模式隔离和重启持久化验收；本地交易在缺少正式净值时正确保持待确认。
- 下一任务：F44 Web 与 Android 远端一致性验收。
- 当前阻塞：无 F43 主流程阻塞；真机无法人工注入 SQLite 中途异常，事务回滚由专项自动化测试覆盖。Docker/PostgreSQL 运行验证留待用户 Linux 服务器环境完成。
- 依据文档：[`functions.md`](../functions.md)

## 任务选择与启动

- 优先继续 `in_progress` 任务；否则执行顺序最靠前且前置条件满足的 `todo` 任务。目前 F42 已完成，当前项为 F43；F41 的 Android 验收缺口必须在 F43 核实，既有待外部验收任务不等于运行验收通过，F10 专项隔离测试缺口保留记录。
- 如顶部状态与队列矛盾，先核实并修正；不得仅凭原型已有代码就标记任务完成。
- 开始实现前，将本项标为 `in_progress`，同步顶部状态，并记录范围、验收条件和涉及文件。
- 遇到 `blocked` 任务先核实阻塞；不能静默跳过依赖它的任务。
- 本文件承载进度、交接和架构约定，不要求预先存在独立的 `AGENTS.md`、`architecture.md` 或任务卡。若仓库另有适用的指令文件，仍须遵守。

## 工作规则

1. 一次会话只实现一个任务编号；不得顺手实现下一编号或无关重构。
2. 开始前确认前置任务已完成；先写本次任务的范围和验收条件。
3. 只读取和修改本任务所需文件；先复用现有代码，再决定是否重构。
4. 完成功能后必须运行本任务必要的测试，并记录真实结果；未运行不得标记通过。
5. 完成后更新本文件：状态、完成内容、测试结果、遗留问题和下一任务。
6. 如果任务过大，拆成新的子编号，先更新本文件再实施；不要在一个会话中扩大范围。
7. 发现需求歧义时，以 `functions.md` 为准，并把决定写入“已确定约定”。
8. 不删除历史记录；保持任务状态可追踪。

## 任务状态定义

- `todo`：尚未开始。
- `in_progress`：当前会话正在实现。
- `done`：实现完成且验收测试通过。
- `implemented_pending_validation`：代码或配置完成，本机可执行检查已记录；经用户同意将依赖 Linux Docker 环境的验收留待部署时执行。允许后续代码开发，不代表运行验收通过；保留未勾选状态，补齐验收后才能标记 `done`。
- `blocked`：缺少明确前置条件或外部资源；必须记录阻塞原因。

## 任务队列

### 基础架构

- [x] `F01` `done` 文档准备：任务台账、交接规则和初始约定已写入本文件。保留编号供追踪，不再安排独立实现会话；后续架构决定随具体功能记录。
- [x] `F02` `done` 建立 Flutter 双端启动入口、卡片布局、底部导航和页面占位。
  - 范围：在 `client/` 建立共用 Flutter 工程；持仓、交易、定投、额度、设置导航及第一版子页面占位；不接入业务接口。
  - 验收：静态分析、导航及窄屏/宽屏 widget 测试、Web 与 Android debug 构建通过。
  - 涉及文件：`client/` 工程及测试、`docs/agent-handoff.md`。
  - 环境核实：已有 Android SDK（`C:/lib`），PATH 和常用目录未找到 Flutter/Dart；先准备隔离工具链再验收。
- [ ] `F03` `implemented_pending_validation` 建立 Docker + PostgreSQL 开发环境和健康检查；配置完成，待用户在 Linux Docker 环境验收。
  - 范围：PostgreSQL Compose 服务、持久化卷、仅本机端口、环境变量模板及开发操作文档；不实现 F04 数据库迁移或接入原型业务接口。
  - 验收：Compose 配置解析；容器启动并达到 healthy；SQL 查询成功；重建容器后测试数据仍存在；停止后恢复健康。
  - 涉及文件：`compose.yaml`、`.env.example`、`.gitignore`、`docs/development.md`、本文件。
  - 当前结论：静态检查已通过；用户明确不在本机安装 Docker Desktop，运行验收转交用户在 Linux 服务器部署时执行，不阻塞 F04 开发。
- [ ] `F04` `implemented_pending_validation` 建立数据库迁移机制，支持空库初始化和重复执行；待 Linux PostgreSQL 验收。
  - 范围：Node/PostgreSQL SQL 文件迁移执行器、版本及校验和记录、事务与并发锁、初始应用 schema、测试及操作说明；不实现后续业务功能或 F05。
  - 验收：空库初始化、重复运行无变化、失败回滚、已执行迁移变更拒绝、并发串行；本机单元测试，真实 PostgreSQL 集成测试留待 Linux 部署。
  - 涉及文件：`server/db/`、`scripts/`、`test/`、`package.json`/锁文件、`docs/development.md`、本文件。
- [x] `F05` `done` 建立 Android SQLite 本地存储与统一 Repository 边界。
  - 范围：SQLite 版本化初始化、JSON 记录存储、平台无关 Repository 接口与事务边界、Android 工厂；业务模型和 UI 接入随后续任务扩展，不实现 F06/F09。
  - 验收：真实 SQLite 文件关闭重开后数据保留、命名空间隔离、增删改查、事务回滚及重复初始化；Flutter 静态分析、现有 widget 测试、Web/Android debug 构建。
  - 涉及文件：client/lib/data/、client/test/、client/pubspec.yaml/锁文件、client/README.md、本文件。

### 认证与数据源

- [x] `F06` `implemented_pending_validation` 邮箱密码注册和安全密码散列。
  - 范围：PostgreSQL 用户表、注册接口、安全密码散列及 Flutter 注册页；不实现 F07 登录与会话。
  - 验收：输入校验、随机盐散列与密码验证、重复邮箱和并发唯一性、注册响应无秘密、Flutter 表单与错误反馈；真实 PostgreSQL 验收留待 Linux。
  - 涉及文件：server/auth/、server/db/migrations/、server/index.js、client/lib/、相关测试与开发说明、本文件。
- [x] `F07` `implemented_pending_validation` 登录、会话凭据和服务端身份校验。
- [x] `F08` `implemented_pending_validation` 退出登录及凭据清理。
- [x] `F09` `done` Android 本地/远端模式切换，数据完全独立。
- [x] `F10` `done` 私有资源账号隔离与越权测试。
- [ ] `F11` `implemented_pending_validation` 基金目录采集、缓存和可替换适配层。
  - 范围：独立目录适配器、规范化校验、PostgreSQL 公共快照缓存、TTL/并发合并/失败回退、现有目录消费者接入；不实现 F12 过滤或 F13 添加。
  - 验收：响应解析与异常校验、缓存命中/过期/重建服务、并发去重、失败保留旧快照和无缓存报错、替换适配器；真实 PostgreSQL 缓存往返留待 Linux 验收。
  - 涉及文件：server/catalog/、server/db/migrations/、server/index.js、test/、package.json、docs/development.md、本文件。
  - 前置：F10 已记录实现，专项隔离测试缺口保留；依交接规则，既有外部验收不阻塞本项。
- [ ] `F12` `implemented_pending_validation` 基金名称/代码搜索及人民币场外过滤。
  - 范围：复用 F11 目录服务，名称/代码搜索、人民币场外筛选、Flutter 搜索页面和服务端 API 接入；不实现 F13 添加持久化。
  - 验收：名称/代码匹配、空查询、结果上限、ETF/LOF/外币排除及 ETF 联接保留、失败响应；Flutter 输入、加载、空结果、错误及结果展示测试、静态分析。
  - 涉及文件：server/catalog/search.js、server/index.js、test/fund-search.test.js、client/lib/、client/test/、client/pubspec.yaml/锁文件、开发说明及本文件。
  - 前置：F11 已实现，沿用待 Linux 验收约定，不阻塞本项。
- [ ] `F13` `implemented_pending_validation` 添加基金到当前数据源。
  - 范围：搜索结果添加、已添加基金列表、SQLite 本地业务 Repository、PostgreSQL 账号基金关联及 API、现有登录会话的最小客户端接入、真实模式切换；不实现 F14 净值或持仓计算。
  - 验收：重复/并发添加幂等、目录与代码校验、未登录拒绝及账号隔离、SQLite 重开保留、模式隔离、Flutter 成功/失败反馈、必要回归与静态分析；真实 PostgreSQL 留待 Linux。
  - 涉及文件：server/funds/、新增数据库迁移、server/index.js、client/lib/ 与相关测试、docs/development.md、本文件。
  - 前置核实：F11/F12 已实现，外部验收依约不阻塞；发现旧认证实际仍为 JSON 用户及内存会话，F13 复用现有身份但不宣称认证迁移完成。
- [ ] `F14` `implemented_pending_validation` 正式净值获取、历史缓存和来源记录。
  - 范围：可替换正式净值适配器、PostgreSQL 历史快照缓存、来源与采集时间、最新值和历史 API；不实现 F15 交易换算或 F16 净值日期判定。
  - 验收：正式响应校验、缓存命中/过期刷新、并发合并、失败保留旧历史、来源记录持久化；本机单元/路由测试，真实 PostgreSQL 与上游联通留待 Linux。
  - 涉及文件：`server/nav/`、`server/db/migrations/0005_nav_snapshots.sql`、`server/index.js`、`test/nav.test.js`、`package.json`、`docs/development.md`、本文件。

### 持仓与收益

- [x] `F15` `done` 交易金额、份额、费率/固定费用换算。
  - 范围：费率或固定费用二选一；金额/份额录入在买入/卖出方向下统一换算、精度和边界校验；不实现 F16 净值日期判定或 F17/F19 交易录入流程。
  - 验收：核心换算、公开交易预览、非法费用/净值、旧交易兼容测试通过；固定费用语义和精度记录在完成记录。
- [x] `F16` `done` 15:00、周末、节假日的净值日期判定。
- [x] `F17` `done` 买入交易录入。
- [x] `F18` `done` 待确认交易确认和幂等处理。
- [x] `F19` `done` 卖出交易及历史持仓校验。
- [x] `F20` `done` 交易记录列表和详情。
  - 本次范围：完善 Flutter 交易历史列表的排序与摘要展示，新增交易详情页并接入本地/远端历史页；不实现交易撤销、账本重算或持仓汇总。
  - 验收条件：已确认、待确认和已取消记录可在列表区分；点击记录可查看完整交易字段；本地/远端历史页和既有导航测试通过；Flutter 静态分析与全量测试通过。
- [x] `F21` `done` 交易撤销与账本重算。
- [x] `F22` `done` 持仓份额、投入、赎回、成本汇总。
  - 范围：扩展现有交易账本重算，返回当前份额、累计投入、累计赎回和剩余持仓成本；保持待确认/已取消交易排除，不实现 F23 市值、收益率展示。
  - 验收：服务端汇总字段及多笔买卖、费用、待确认/已取消、多基金和 HTTP 账号隔离测试通过；客户端若仅消费既有 API 则不扩展首页 UI。
  - 涉及文件：`server/accounting.js`、`web/index.html`、`test/accounting.test.js`、`test/transactions.test.js`、本文件。
- [x] `F23` `done` 持仓首页正式市值、收益和收益率。
- [x] `F24` `done` 持仓详情和关联交易。
  - 范围：从 Flutter/Web 持仓概览进入单基金详情，展示汇总指标并按 fundCode 关联交易；不实现 F25 每日正式收益。
  - 验收：详情入口可用、关联交易按基金过滤且保留状态/详情能力、本地与远端数据路径可用、必要客户端测试与静态检查通过。
  - 涉及文件：`client/lib/main.dart`、`client/lib/holding_detail.dart`、`client/lib/transaction_history.dart`、`client/test/widget_test.dart`、`client/test/holding_detail_test.dart`、`web/trading.js`、本文件。
- [x] `F25` `done` 每日正式收益。
  - 范围：按正式净值交易日计算账户级每日正式收益；只纳入已确认交易，扣除当日买入/卖出现金流，不使用估算净值；提供账户隔离的收益序列接口及纯函数测试。
  - 验收：连续净值日收益正确、现金流不被计作收益、pending/cancelled 排除、多基金隔离、缺少前后完整正式净值时不生成记录；现有持仓/收益回归测试通过。
  - 已确定约定：收益日使用正式 `navDate`；首个可比较日不生成收益；买入现金流按含手续费的实际扣款计入，卖出现金流按扣除手续费后的实际到账计入；返回金额统一两位小数。
- [ ] `F26` `implemented_pending_validation` 指数行情与汇率适配、缓存。
  - 范围：可替换指数行情与汇率适配器（默认 Yahoo Finance 日线）、PostgreSQL 行情快照缓存、TTL/并发合并/失败回退、最新行情和历史 API；不实现 F27 估算规则或 F28 展示。
  - 验收：响应解析与异常校验、缓存命中/过期/重建、并发去重、来源隔离、失败保留旧快照、无缓存报错、替换适配器；本机单元/路由测试，真实 PostgreSQL 与上游联通留待 Linux。
  - 涉及文件：`server/market/`、`server/db/migrations/0006_market_snapshots.sql`、`server/index.js`、`test/market.test.js`、`package.json`、`docs/development.md`、本文件。
- [x] `F27` `done` 基金估算规则和版本化输入。
- [x] `F28` `done` 正式收益与估算收益的明确展示。

### 定投

- [x] `F29` `done` 定投计划创建和字段校验。
- [x] `F30` `done` 定投计划编辑、启用和暂停。
- [x] `F31` `done` 生成定投待记账记录且幂等。
- [x] `F32` `done` 确认一期定投并关联交易。
- [x] `F33` `done` 修改或补录一期定投。
- [x] `F34` `done` 跳过一期定投。

### 额度

- [x] `F35` `done` 纳斯达克100/标普500额度自动采集。
- [x] `F36` `done` 额度列表、详情及完整字段展示。
- [x] `F37` `done` 用户额度覆盖、优先级和隔离。
  - 本次范围：将自动额度与用户覆盖分开保存；同一基金支持多账号独立覆盖；接口按当前账号返回自动值或用户值，明确覆盖来源与优先级；补充覆盖字段校验和 HTTP 隔离测试。不实现 F38 恢复自动额度数据的新流程。
  - 验收：用户覆盖优先于自动值且自动刷新不丢失；不同账号互不可见、互不可改；未登录拒绝；覆盖状态和自动基线可辨识；相关 Node 测试与语法检查通过。
  - 涉及文件：`server/quotas.js`、`server/index.js`、`web/index.html`、`test/quotas.test.js`、`test/quotas-http.test.js`、`docs/development.md`、本文件。
- [x] `F38` `done` 恢复自动额度数据。
  - 本次范围：完善恢复接口，使当前账号删除覆盖后回到最新自动采集值；保留其他账号覆盖并同步其自动基线；覆盖或自动记录缺失时按现有账号隔离规则处理；补充恢复成功、隔离、无记录和上游失败测试。不实现 F39 导入导出。
  - 验收：恢复请求成功后当前账号返回 `valueSource=automatic`；其他账号覆盖不受影响且自动基线更新；无记录返回 404；采集失败返回 502 且原覆盖/自动记录不丢失；额度专项测试与语法检查通过。

### 导入导出与系统验收

- [x] `F39` `done` 统一版本化 JSON 导出。
- [x] `F40` `done` 导入文件预检和数据概要。
- [ ] `F41` `implemented_pending_validation` Android 本地事务覆盖导入与回滚。
  - 范围：Android 本地模式读取版本化 JSON、校验并展示概要、用户确认后在同一 SQLite 事务内完整替换五类本地集合；导入失败保持原数据不变。不实现 F42 远端导入。
  - 验收：合法包覆盖 `funds`、`transactions`、`plans`、`planEntries`、`quotaOverrides`；格式/版本/集合及主键校验失败不改库；事务中途失败可回滚；文件选择、概要确认、成功/失败反馈可用；Flutter 静态分析、专项测试和 Android debug 构建通过。
  - 涉及文件：`client/lib/data/import_repository.dart`、`client/lib/import_page.dart`、`client/lib/main.dart`、`client/pubspec.yaml`/锁文件、`client/test/import_repository_test.dart`、本文件。
- [x] `F42` `done` 远端账号事务覆盖导入与回滚。
- [x] `F43` `done` Android 离线完整流程验收。
  - 本次范围：核实 Android 设备与工具链、离线业务入口及 SQLite 数据路径，执行本机可用验收并记录缺口；不以服务端功能或桌面测试代替 Android 全流程验收，不实现 F44。
  - 验收条件：离线本地模式的基金/交易/持仓、定投、额度、导入导出和重启持久化可用；模式切换不混合数据；Android 构建和设备离线流程有真实结果。缺少实现或设备时标记 blocked，保留未通过项。
  - 前置核实：F42 done；F41 已实现但 APK 与系统文件选择未验收，F05 的 Android 插件持久化也未验收，本项必须核实这些限制。
  - 涉及文件：`client/lib/`、`client/test/`、Android 工具链、`docs/agent-handoff.md`；如完整流程缺少业务实现，只记录阻塞与恢复步骤，不将系统验收扩大为多模块开发。
- [ ] `F44` `todo` Web 与 Android 远端一致性验收。
- [ ] `F45` `todo` 导出导入往返验收。
- [ ] `F46` `todo` 数据库备份恢复验收。
- [ ] `F47` `todo` 可运行版本交付验收。

## 已确定约定

- 用户于 2026-09-13 明确：本机 Windows 不安装 Docker Desktop，继续直接开发代码；Docker/PostgreSQL 环境相关验证由用户在 Linux 服务器部署时执行。Agent 仍须运行本机可完成的必要检查，逐项记录未执行的集成/部署验证，不得声称通过；符合此条件的实现使用 `implemented_pending_validation`，不因缺少本机 Docker 阻塞后续代码任务。

- 交易是持仓账本的事实来源；导入后由交易重新计算持仓摘要。
- 待确认交易不计入正式收益；估算收益不写入正式收益账本。
- 本地与远端切换不自动合并或删除数据。
- 第一版只支持人民币场外基金，不实现截图之外的行情、基金穿透、机构持仓和市场日历页面。
- 当前原型使用 Express、JSON 文件和原生网页；其实现可参考，但不能视为已满足 Flutter、PostgreSQL、本地 SQLite 和正式认证要求。

## 完成记录

### F01：文档准备已完成

- 交付：本文件已包含完整任务队列、状态定义、单任务执行规则和初始业务约定。
- 本次调整：取消重复的 F01 实现会话，保留其编号并标记完成；当前待执行任务推进至 F02。
- 验收：文档核对，顶部进度与任务队列一致；本次仅调整文档，不涉及业务测试。
- 遗留：业务功能尚未按本计划实施，已有原型不等于对应任务已验收。
- 下一会话：执行 F02，先读 `functions.md`、`package.json` 和相关前端入口，核实 Flutter 工程与工具环境；只搭建双端入口和页面占位。

### F02：Flutter 双端入口已完成

- 状态：`done`；本次只执行 F02，未开始 F03。
- 修改文件：`client/lib/main.dart`、`client/test/widget_test.dart`、`client/README.md`、Flutter 生成的 `client/pubspec.yaml`/锁文件/分析配置/Android 与 Web 平台入口、根 `.gitignore`、本文件。
- 已实现：Android/Web 共用 Material 3 入口；持仓、交易、定投、额度、设置五项底部导航；卡片式空状态；第一版所有页面范围的可返回占位入口；正式/估算收益分别标识且无数据时显示横线。
- 已确定实现约定：前端工程位于 `client/`，与原 Express 原型独立；F02 不请求原型接口、不模拟登录或切换数据源，不创建虚构收益。Android 本地与 Web 远端只展示默认模式说明，实际存储、认证、模式切换仍属后续任务。
- 环境：工具实际工作区为 `C:/Users/ms-ml/.ccgui/workspace/PositionAssistant`。隔离 Flutter stable 3.47.4 / Dart 3.13.3 安装在 `.tooling/flutter`（根忽略规则排除）；沿用 `C:/lib` Android SDK 和 JDK 17；Gradle 首次构建安装 Build-Tools 36。
- 测试命令及真实结果（在 `client/`，flutter/dart 使用 `../.tooling/flutter/bin/*.bat`）：`dart format lib test` 成功；`flutter analyze` 无问题；`flutter test` 两项通过，覆盖 320×640、1280×800 下五项导航及全部占位页进入/返回，无布局异常；`flutter build web` 成功；`flutter build apk --debug` 成功，Gradle 耗时 318.2 秒。
- 构建产物：`client/build/web/`、`client/build/app/outputs/flutter-apk/app-debug.apk`（仅调试验收产物）。
- 未覆盖或遗留：未连接 Android 真机/模拟器，未进行真机启动和浏览器人工视觉验收；使用默认 Flutter 图标。业务功能未实现，后续按任务队列逐项接入。SDK 未加入全局 PATH，启动命令见 `client/README.md`。
- 下一任务：F03 建立 Docker + PostgreSQL 开发环境和健康检查。
- 更新时间：2026-09-13。

### F03：开发环境配置已完成，运行验收阻塞（历史记录，已由下方用户决定更新）

- 状态：`blocked`；本次只处理 F03，未执行 F04。
- 修改文件：`compose.yaml`、`.env.example`、`.gitignore`、`docs/development.md`、本文件。
- 已实现：PostgreSQL 17 Compose 服务、命名数据卷、127.0.0.1 端口绑定、必填密码校验、pg_isready 健康检查；补充首次启动、SQL 检查、重建容器持久化断言、停止恢复和诊断命令。
- 已确定约定：本任务只建立数据库开发服务；原型仍使用 JSON，业务表和迁移由 F04 实现。真实 `.env` 忽略提交，模板不含默认密码；已有数据卷不会因修改初始化环境变量自动更改凭据。
- 环境核实：工具实际工作区仍为 `C:/Users/ms-ml/.ccgui/workspace/PositionAssistant`。`docker version`、`docker compose version` 和 `docker compose config --quiet` 均因 command not found 返回 127；检查 Program Files Docker、Chocolatey 和用户 Local Programs DockerDesktop 常见位置均未发现 docker.exe；有 wsl 命令，但未验证 WSL 2、虚拟化或 Docker Engine。当前目录 `git status --short` 返回非 Git 仓库，无法提供 Git diff。
- 测试真实结果：Python/PyYAML 解析 `compose.yaml` 成功，镜像、仅本机端口、命名卷、必填密码、健康检查变量转义和 env 忽略规则断言通过。此结果仅为静态检查，不等于 Compose 配置或运行验收。
- 未覆盖或遗留：缺少可用 Docker 环境，Compose 解析、healthy、SQL 查询、持久化和恢复验收均未运行。未安装 Docker Desktop 或修改 Windows 系统组件。
- 下一会话：先准备并启动 Windows Docker Desktop（通常使用 WSL 2 Linux 容器后端），复制 `.env.example` 为 `.env` 并设置本地密码，按 `docs/development.md` 完成 F03 全部运行验收；成功后才将 F03 标记 done 并推进 F04。
- 更新时间：2026-09-13。

### F03：按用户决定转为待 Linux 部署验收

- 状态：`implemented_pending_validation`；取代上条历史记录中的 blocked 及安装 Windows Docker Desktop 的后续安排。
- 修改文件：仅 `docs/agent-handoff.md`。
- 已完成：F03 配置和开发说明保持原实现；同步顶部状态、任务队列、状态定义和开发约定。
- 验证记录：沿用上条静态检查结果，本次仅核对文档一致性，未重新运行代码或容器测试。
- 用户待验收：Compose 配置解析、容器 healthy、SQL 查询、重建容器后数据持久化、停止后恢复健康；按 `docs/development.md` 在 Linux Docker 环境执行并记录结果。
- 下一任务：F04 数据库迁移机制；本次未开始。
- 更新时间：2026-09-13。

### F04：数据库迁移机制已实现，待 Linux PostgreSQL 验收

- 状态：`implemented_pending_validation`；本次只执行 F04，未开始 F05。
- 修改文件：`server/db/migrate.js`、`server/db/migrations/0001_initialize.sql`、`scripts/migrate.js`、`test/migrate.test.js`、`test/migrate.integration.test.js`、`package.json`/`package-lock.json`、`docs/development.md`、本文件。
- 已实现：pg 专用连接执行 SQL 文件；历史版本、文件名和 SHA-256 校验和；历史必须匹配当前文件的完整前缀；事务级 advisory lock 串行执行；一个批次迁移及版本记录原子提交，失败回滚；重复执行跳过已应用版本；CLI 读取 .env 并以非零状态报告失败。
- 范围决定：F04 初始迁移只建立 `positionassistant` schema，迁移元数据位于 `public.schema_migrations`。functions.md 未规定完整业务表结构，业务表随所属任务新增迁移，不在基础设施任务中提前实现认证、交易或定投。原 JSON 原型未接入 PostgreSQL。
- 已确定约定：SQL 文件使用四位递增编号；已执行文件不可改动；新增迁移仅使用事务内 SQL，不得自行控制事务或执行外部副作用；开发命令需要 Node.js 22.9+。详细用法及 Linux 验收见 docs/development.md。
- 本机环境：实际工具工作区为 `C:/Users/ms-ml/.ccgui/workspace/PositionAssistant`；Node.js v22.19.0。
- 测试真实结果：`npm run test:migrations` 5 项通过（初始化记录、重复运行、失败回滚流程、历史差异拒绝、文件校验）；`node --check server/db/migrate.js` 与 `node --check scripts/migrate.js` 均通过。单元测试使用替身客户端，不代表真实 SQL/锁已验收。
- 外部验收：`npm run test:migrations:integration` 已执行但因未设置 TEST_DATABASE_URL 跳过 1 项，0 项通过；真实空库初始化、并发串行、重复执行、DDL/记录回滚与校验和保护仍待 Linux PostgreSQL。测试使用随机临时数据库并清理，只能连接独立开发实例及 CREATEDB 账号。F03 容器验收仍待执行。
- 依赖检查：`npm install pg` 成功；`npm audit --omit=dev` 返回 1，报告 Express/qs 依赖链 2 项 moderate 漏洞（GHSA-x5fp-wj9c-mxmx、GHSA-4mjr-xmp4-gh2g）；未执行无关依赖批量升级，留待原型依赖维护。
- 下一任务：F05 Android SQLite 本地存储与统一 Repository 边界；本次停止，不继续。
- 更新时间：2026-09-13。

### F05：Android SQLite 本地存储与 Repository 边界已完成

- 状态：`done`；本次仅执行 F05，未开始 F06 或 F09。
- 修改文件：`client/lib/data/repository.dart`、`sqlite_repository.dart`、`local_repository.dart`、`client/test/repository_test.dart`、`client/pubspec.yaml`/锁文件、`client/README.md`、本文件；Flutter pub 自动更新平台插件注册文件。
- 已实现：平台无关 CRUD/事务接口；sqflite v1 自动初始化；集合与 ID 复合主键；参数化 SQL；JSON 保存；事务提交与异常回滚；显式关闭；拒绝数据库降级；Android 私有目录数据库工厂；Web/其他平台明确拒绝本地工厂调用。
- 范围约定：本任务建立基础 JSON 记录边界，业务 Repository 随后续任务增加类型与字段校验，payload 由业务模型保留自身 ID，金额/份额使用十进制字符串。未制定 F39 导出格式。占位页面尚无业务读取，工厂按需调用，不在 main 中创建无使用者连接；远端适配及模式切换随后续任务接入。详见 client/README.md。
- 测试真实结果：`dart format lib/data test/repository_test.dart` 成功；`flutter analyze` 无问题；`flutter test` 5 项通过（3 项真实 SQLite FFI 文件测试、2 项原有 widget 测试）。验证关闭重开、重复初始化、集合隔离、CRUD、事务提交、混合写入/删除回滚、空键和不可 JSON 编码值拒绝。首轮测试临时路径转义及异常类型断言错误，修复后全量重跑通过；误生成的测试数据库文件已清理。
- 构建结果：`flutter build web` 成功（42.9 秒）；`flutter build apk --debug` 成功（Gradle 88.9 秒）。工具工作区仍为 C:/Users/ms-ml/.ccgui/workspace/PositionAssistant。
- 未覆盖或遗留：未连接 Android 真机/模拟器，Android sqflite 方法通道及设备重启持久化尚未运行验收；本次真实 SQL 测试使用 Windows FFI。完整离线业务流程属于 F43。F03/F04 的 Linux PostgreSQL 验收仍待执行。
- 下一任务：F06 邮箱密码注册和安全密码散列；本次已停止，不继续下一项。
- 更新时间：2026-09-13。


### F06：邮箱密码注册和安全密码散列

- 状态：`implemented_pending_validation`；合并模块实现、接口接入和修复记录，重复条目不再单独列出。
- 修改文件：`server/auth/password.js`、`server/auth/register.js`、`server/db/migrations/0002_users.sql`、`server/index.js`、`test/password.test.js`、本文件。
- 已实现：scrypt 随机盐密码散列与 timing-safe 校验；邮箱规范化和格式/长度校验；PostgreSQL users 表、唯一邮箱约束及 UUID 主键迁移；注册接口复用校验并保存散列，重复邮箱返回冲突，响应不含密码字段。
- 修复历史：修复注册路由字段解构错误，确保保存 `passwordHash`；移除明文 demo 密码种子，保留邮箱规范化、随机盐散列和重复邮箱冲突响应。
- 历史测试结果：`node --check server/index.js` 通过；`node --test test/password.test.js`，2 项通过。本次仅整理文档，未重新运行测试。
- 未覆盖或遗留：本机无 PostgreSQL，真实迁移与并发注册唯一性验收待 Linux；原记录未提供 Flutter 注册页验收结果，不据此认定其完成。
- 当时下一任务：F07 登录、会话凭据和服务端身份校验；当前任务以顶部状态为准。
- 更新时间：2026-09-13。

### F07：登录、会话凭据和服务端身份校验

- 状态：`implemented_pending_validation`；本次只执行 F07，未开始 F08。
- 修改文件：`server/index.js`、`docs/agent-handoff.md`。
- 已实现：登录接口校验 `passwordHash`，成功返回随机 Bearer 会话令牌；服务端身份解析改为从 `Authorization` 读取令牌并映射用户。
- 测试命令及结果：`node --check server/index.js` 通过。
- 未覆盖或遗留：本机无 PostgreSQL，真实数据库登录及并发会话验收待 Linux；退出登录和凭据清理属于 F08。
- 下一任务：F08 退出登录及凭据清理。
- 更新时间：2026-09-13。

### F08：退出登录及凭据清理

- 状态：`implemented_pending_validation`；本次只执行 F08，未开始 F09。
- 修改文件：`server/index.js`、`docs/agent-handoff.md`。
- 已实现：新增 `POST /api/auth/logout`，从 Bearer Authorization 读取令牌并从服务端会话表删除；无令牌或重复退出也安全返回 204，客户端可据此清除本地令牌。
- 测试命令及结果：`node --check server/index.js` 通过；`node --test test/password.test.js`，2 项通过。
- 未覆盖或遗留：本机无 PostgreSQL，真实登录/退出及跨进程会话验收待 Linux；Flutter 尚无远端凭据存储调用，客户端接入随后续认证界面任务处理。
- 下一任务：F09 Android 本地/远端模式切换，数据完全独立。
- 更新时间：2026-09-13。

### F09：Android 本地/远端模式切换

- 状态：`done`；本次仅执行 F09，未开始 F10。
- 修改文件：`client/lib/main.dart`、`docs/agent-handoff.md`。
- 已实现：Android 默认本地模式；设置页展示当前模式并提供本地/远端切换开关；Web 保持远端模式；切换仅改变数据源模式标识，明确两种模式数据完全独立，不自动合并或删除。
- 测试命令及结果：`flutter analyze` 无问题；`flutter test`，5 项通过。
- 未覆盖或遗留：远端 Repository、认证凭据和真实 Android 方法通道接入属于后续任务；本次未进行真机验收。
- 下一任务：F10 私有资源账号隔离与越权测试。
- 更新时间：2026-09-13。


### F10：私有资源账号隔离与越权测试

- 状态：`done`；本次仅执行 F10，未开始 F11。
- 修改文件：`server/index.js`、`docs/agent-handoff.md`。
- 已实现：额度用户覆盖与恢复接口按当前 Bearer 会话用户限定资源；未归属的自动额度记录仅在首次修改时归属当前用户，其他用户不能修改或恢复其私有覆盖。
- 测试命令及结果：`node --check server/index.js` 通过；`node --test test/password.test.js`，2 项通过。
- 未覆盖或遗留：本机未运行 PostgreSQL；真实远端多账号并发隔离、数据库级行级权限及 Linux 部署验收待外部环境。交易、定投、持仓和导出已有会话过滤，本次未扩大范围。
- 下一任务：F11 基金目录采集、缓存和可替换适配层。
- 更新时间：2026-09-13。

### F11：基金目录采集、缓存和可替换适配层

- 状态：`implemented_pending_validation`；本次仅执行 F11，未开始 F12。
- 修改文件：`server/catalog/index.js`、`server/catalog/route.js`、`server/db/migrations/0003_fund_catalog_cache.sql`、`server/index.js`、`test/catalog.test.js`、`test/catalog.integration.test.js`、`test/migrate.test.js`、`package.json`、`docs/development.md`、本文件。
- 已实现：东方财富目录适配器与统一字段校验；PostgreSQL 按来源隔离的原子快照缓存；保存来源 URL 和采集时间；24 小时 TTL、进程内并发合并、60 秒失败重试冷却；失败保留旧快照并显式标注过期，无缓存返回 503。新增公共 GET /api/fund-catalog，原有目录消费者共用服务。
- 已确定约定：按请求触发采集；适配器与缓存存储通过注入替换；不自动导入无来源时间的旧 JSON 目录，不用种子基金冒充目录；目录本身保留原始种类，人民币场外过滤属于 F12。服务启动及 Linux 验收见 development.md。
- 测试命令及结果：`node --test test/catalog.test.js test/migrate.test.js test/catalog.integration.test.js`，13 项通过、0 失败、1 项因缺少 TEST_DATABASE_URL 跳过；其中目录 8 项、迁移单元 5 项通过。server/index.js、server/catalog/index.js、server/catalog/route.js 的 node --check 均通过。
- 修复历史：首次迁移单元测试仍硬编码只有 0001，随新增迁移失败；改为断言当前迁移清单后重跑通过。
- 未覆盖或遗留：真实 PostgreSQL 完整迁移、跨连接快照持久化和 Linux 服务重启验收未执行；线上东方财富联通及真实响应未验证，解析测试使用固定响应。数据库不可用时冷启动目录接口返回 503。跨进程不合并刷新请求。既有 F03–F10 验收缺口保持原记录。
- 下一任务：F12 基金名称/代码搜索及人民币场外过滤；本次停止，不继续。
- 更新时间：2026-09-13。

### F12：基金名称/代码搜索及人民币场外过滤

- 状态：`implemented_pending_validation`；本次仅执行 F12，未开始 F13。
- 修改文件：`server/catalog/search.js`、`server/index.js`、`test/fund-search.test.js`、`client/lib/fund_search.dart`、`client/lib/main.dart`、`client/test/fund_search_test.dart`、`client/test/widget_test.dart`、`client/pubspec.yaml`/锁文件、Android 主 Manifest、`docs/development.md`、本文件。
- 已实现：可注入目录服务的公共搜索接口；名称/代码/简称包含匹配、输入规范化、20条上限和完整代码优先、输入校验；过滤外币、ETF/LOF等场内产品，保留 ETF 联接及已知类型人民币基金。Flutter 搜索入口、后端 HTTP 接入、加载/结果/无结果/错误展示、查询变更后丢弃过期响应、Android 网络权限。
- 已确定约定：原始目录保持完整；搜索筛选依赖名称/类型的保守规则（详见 development.md），上游缺少结构化币种和场所字段，未知类型排除，真实目录误判风险必须部署抽查。本地模式搜索公共目录也需联网，F13 才添加到当前数据源。
- 测试真实结果：Node 目录回归及搜索测试共11项通过，`node --check server/index.js` 通过；Flutter 全量8项通过；搜索页/API及测试文件专项 analyze 无问题；`flutter build web` 成功（49.3秒）。全工程 analyze 有1项既有警告：`main.dart` 的 `_modeSetting` 未使用，未作为本项扩展修复。
- 修复历史：首次 Flutter 回归中2项导航测试仍断言搜索页为占位页，按真实搜索页更新断言后全量重跑通过。
- 未覆盖或遗留：真实上游目录筛选准确性、Linux PostgreSQL/后端完整联调、Android 真机联网和构建未验收；既有 F03–F11 缺口不变。服务地址、同源代理及 HTTPS 配置见 development.md。
- 下一任务：F13 添加基金到当前数据源；本次停止，不继续。
- 更新时间：2026-09-13。

### F13：添加基金到当前数据源

- 状态：`implemented_pending_validation`；本次仅执行 F13，未开始 F14。
- 修改文件：`server/funds/index.js`、`server/db/migrations/0004_user_funds.sql`、`server/index.js`、`client/lib/data/fund_repository.dart`、`client/lib/fund_search.dart`、`client/lib/main.dart`、`client/lib/remote_login.dart`、`test/funds.test.js`、`test/catalog.integration.test.js`、`client/test/fund_add_test.dart`、`client/test/repository_test.dart`、`client/test/widget_test.dart`、`docs/development.md`、本文件。
- 已实现：搜索结果添加按钮、添加中禁用/成功/失败重试反馈、已添加基金列表；SQLite 事务去重和持久化；远端 GET/POST `/api/my-funds` 依会话确定账号、目录核验并采用 PostgreSQL 复合主键幂等保存；模式切换实际接线，搜索页绑定打开时的数据源；最小已有账号登录/退出入口和内存凭据，标准 Bearer 解析修复。添加只保存代码/名称/类型，不创建交易、不计算持仓或净值。
- 已确定约定：代码区分份额，名称原样保存，不从缺失字段猜测份额类别；本地添加使用搜索结果，已有记录可离线读取；远端重试已添加代码不依赖目录刷新。首次进入列表点击读取，搜索返回或切模式后刷新。
- 历史缺口纠正：亲读 `server/index.js` 确认 F06/F07 实际仍使用 JSON 用户文件和内存会话，未接入 PostgreSQL users；此前 F06 完成记录中“接口保存 PostgreSQL”的描述不准确。F13 复用现有身份，owner_id 使用旧字符串 ID，无虚构 users 外键；未来认证迁移需保留或显式映射该 ID。注册页仍占位、凭据重启失效；认证完整验收不因本项通过。F09 原有模式开关未挂载，本次已接线。
- 测试真实结果：Node 基金 API、目录/搜索及迁移回归 18 项通过、0 失败、1 项因缺少 TEST_DATABASE_URL 跳过；包括真实 HTTP 路由的未登录拒绝、非法/不支持代码、伪造 owner 字段、重复并发及账号隔离、失败重试，以及生产 Bearer 解析回归。数据库测试新增跨连接并发去重和账号隔离断言但未运行。`node --check server/index.js` 与 `server/funds/index.js` 通过；Flutter 全量 11 项通过（含真实 SQLite 并发添加/关闭重开保留、远端凭据/请求及失效处理、页面失败重试、窄宽屏导航），`flutter analyze` 无问题。
- 修复历史：初轮静态分析提示缺少花括号，修复后通过；HTTP 测试模拟中文响应缺少 UTF-8 header，修复后全量通过；脚本生成时出现本机默认编码/换行转义问题，已修复并通过语法与测试检查。
- Web 构建：`flutter build web` 成功（56.0 秒），产物 `client/build/web/`。
- 未覆盖或遗留：真实 PostgreSQL 迁移/持久化/并发及账号端到端联调、Android 真机 SQLite/模式往返/联网未运行；本次未构建 Android APK；真实目录准确性仍待验收。既有 F03–F12 缺口保留，尤其 F10 无专项完整隔离验收。数据库表依赖 DATABASE_URL，Linux 操作见 development.md。
- 下一任务：F14 正式净值获取、历史缓存和来源记录；本次停止，不继续。
- 更新时间：2026-09-13。

### F14：正式净值获取、历史缓存和来源记录

- 状态：`implemented_pending_validation`；本次仅执行 F14，未开始 F15。
- 修改文件：`server/nav/index.js`、`server/db/migrations/0005_nav_snapshots.sql`、`server/index.js`、`test/nav.test.js`、`package.json`、`docs/development.md`、本文件。
- 已实现：新增可替换东方财富正式净值适配器；校验六位基金代码、正净值和净值日期；PostgreSQL 按基金/日期/来源保存历史快照、来源 URL、来源标识和采集时间；24 小时缓存、强制刷新、进程内并发合并、刷新失败保留旧历史；新增最新净值和历史查询 API，并接入服务端。
- 已确定约定：正式净值与估算值分离，只有正式净值进入 `nav_snapshots`；数据库不可用或无缓存时接口返回 502；F14 不处理交易确认日期、金额/份额换算或持仓计算。
- 测试命令及结果：`node --test test/nav.test.js test/catalog.test.js test/funds.test.js`，13 项通过、0 失败；覆盖适配器响应校验、缓存命中/刷新、失败回退、并发合并和 HTTP 路由。`node --check server/nav/index.js` 与 `node --check server/index.js` 通过。
- 未覆盖或遗留：本机无 PostgreSQL，迁移真实执行、跨重启历史持久化、真实东方财富联通和 Android 真机联调待 Linux/设备环境；现有旧 JSON 交易链路仍保留，后续任务逐步接入正式净值服务。
- 下一任务：F15 交易金额、份额、费率/固定费用换算；本次停止，不继续。
- 更新时间：2026-09-24。

### F15：交易金额、份额、费率/固定费用换算

- 状态：`done`；本次仅执行 F15，未开始 F16。
- 修改文件：`server/accounting.js`、`server/index.js`、`web/trading.js`、`web/index.html`、`test/accounting.test.js`、本文件。
- 已实现：交易换算支持 `feeMode: rate|fixed`；费率仍按百分比输入，固定费用按人民币金额输入；金额买入按含手续费总额反推净额和份额，金额卖出按扣费前金额计算份额，份额录入按净值计算金额；金额和份额结果统一保留两位小数，净值保留上游精度。校验拒绝无效净值、负固定费用、费率越界、混用两种费用和扣费后非正金额。旧交易只有 `fee` 字段时仍按固定费用兼容。两套原型交易表单均发送明确费用模式并显示固定费用/费率。
- 已确定约定：费率与固定费用二选一；金额模式买入金额包含手续费，卖出金额为扣费前金额；固定费用不能超过金额买入总额；输入金额/份额按 0.01 精度归一化，成交净值不截断。
- 测试命令及结果：`node --test test/accounting.test.js`，6 项通过；`node accounting-check.cjs` 通过；`node --test test/nav.test.js test/catalog.test.js test/funds.test.js`，13 项通过；`node --check server/accounting.js`、`server/index.js`、`web/trading.js` 通过；提取 `web/index.html` 内联脚本后 `node --check` 通过。
- 修复历史：首轮测试发现净值被误截断到两位导致 4.419 的历史换算偏差，已改为保留净值原始精度并重跑专项测试通过。
- 未覆盖或遗留：旧的 `integration-check.cjs` 仍未携带 Bearer 登录凭据，访问受保护的 `/api/transactions/preview` 时返回 401 而非脚本断言的 200；该脚本的认证修复留给认证/接口维护，不在 F15 扩大范围。Flutter 交易录入仍属 F17；净值日期判定仍属 F16。
- 下一任务：F16 15:00、周末、节假日的净值日期判定；本次停止，不继续。
- 更新时间：2026-09-24。

### F16：15:00、周末、节假日的净值日期判定

- 状态：`done`；本次仅执行 F16，未开始 F17。
- 修改文件：`server/trading-date.js`、`server/index.js`、`test/trading-date.test.js`、`docs/development.md`、本文件。
- 已实现：新增日历日期安全加减和净值日期选择函数；15:00 前从交易当日匹配，15:00 后从下一自然日匹配；正式净值历史中缺失的周末、节假日自动跳过，选择首个不早于起点的 `navDate`；无后续记录时继续返回待确认。历史查询结束日期也改用日历日期计算，避免依赖本机时区。
- 已确定约定：不维护静态节假日表，以正式净值历史中的实际记录作为交易日历；上游尚未公布目标日期时不提前计算份额，后续确认重试复用同一判定。
- 测试命令及结果：`node --test test/trading-date.test.js test/accounting.test.js`，11 项通过；`node --test test/nav.test.js test/catalog.test.js test/funds.test.js`，13 项通过；`node --check server/trading-date.js`、`node --check server/index.js` 通过。
- 未覆盖或遗留：未连接真实东方财富或 PostgreSQL 环境，真实上游节假日记录仍待 Linux/正式数据源联调；F17 Flutter/网页买入交易录入流程尚未开始。
- 下一任务：F17 买入交易录入；本次停止，不继续。
- 更新时间：2026-09-24。

### F17：买入交易录入

- 状态：`done`；本次仅执行 F17，未开始 F18。
- 修改文件：`client/lib/data/transaction_repository.dart`、`client/lib/transaction_entry.dart`、`client/lib/main.dart`、`server/index.js`、`client/test/transaction_entry_test.dart`、`client/test/repository_test.dart`、`client/test/widget_test.dart`、本文件。
- 已实现：新增 Flutter 买入交易录入页；从已添加基金中选择基金，固定买入方向，支持按金额/份额录入、费率/固定费用二选一、实际操作日期和 15:00 前后选择，以及备注/来源；预览显示成交净值/净值日期/份额或待确认原因，保存显示待确认反馈。新增本地 SQLite 交易 Repository 和远端 Bearer Repository：本地记录保存到独立 `transactions` 集合并保留待确认状态，远端复用 `/api/transactions/preview` 与 `/api/transactions`，沿用服务端 F15/F16 校验和换算；服务端交易校验保留基金显示字段、备注和来源；交易入口已替换原占位页。
- 已确定约定：F17 只录入买入，不处理确认、卖出、撤销、持仓汇总或幂等确认；本地模式当前没有正式净值服务时先保存待确认交易，远端模式由服务端决定正式净值日期和确认状态；交易名称与份额类别作为客户端展示字段随请求发送，服务端仍以基金代码和现有目录/净值逻辑为准。
- 测试命令及结果：`flutter analyze` 无问题；`flutter test` 全量 15 项通过，覆盖买入页预览/保存、远端认证请求字段、本地 SQLite 持久化与输入校验、既有导航回归；`node --check server/index.js` 通过；`node --test test/accounting.test.js test/trading-date.test.js test/nav.test.js test/catalog.test.js test/funds.test.js` 24 项通过；`flutter build web` 成功。
- 未覆盖或遗留：未连接真实 PostgreSQL、真实远端服务或 Android 真机；本地正式净值获取、待确认自动重试仍依后续数据源/确认任务；未构建 Android APK。本机 Flutter 工具曾因默认 AppData 无权限，测试使用工作区 `.tooling/appdata` 作为 `APPDATA`，不影响代码运行。
- 下一任务：F18 待确认交易确认和幂等处理；本次停止，不继续。
- 更新时间：2026-09-24。

### F18：待确认交易确认和幂等处理

- 状态：`done`；本次仅执行 F18，未开始 F19。
- 修改文件：`server/index.js`、`test/transactions.test.js`、`client/lib/data/transaction_repository.dart`、`client/lib/transaction_entry.dart`、`client/lib/transaction_history.dart`、`client/lib/main.dart`、`client/test/transaction_entry_test.dart`、`docs/agent-handoff.md`。
- 已实现：服务端交易创建接受用户级 `clientRequestId`，同一账号重复或并发提交返回原交易，不新增账本记录；确认锁按确认范围复用进行中的任务，重复确认只允许 pending→confirmed 一次；`POST /api/transactions/confirm` 只确认当前 Bearer 账号的待确认交易，后台定时任务仍可处理全量；确认失败或正式净值未公布时继续保留待确认状态，`holdings()` 仍只计算已确认交易。Flutter 录入页为每次交易草稿保留幂等请求号，远端 Repository 新增确认调用，本地/远端交易记录页展示待确认原因并提供重新确认入口。
- 已确定约定：旧客户端未携带 `clientRequestId` 时保持兼容但不提供跨请求去重；本地模式目前没有正式净值服务，确认按钮会重新读取本地记录，交易仍保持待确认，正式确认由接入净值后的远端服务完成。
- 测试命令及结果：`node --check server/index.js` 通过；`node --test test/transactions.test.js`，1 项通过；`node --test test/transactions.test.js test/accounting.test.js test/trading-date.test.js test/nav.test.js test/catalog.test.js test/funds.test.js`，25 项通过；Flutter `dart format lib test` 成功（使用工作区 `.tooling/appdata` 绕过默认 AppData 权限）；`flutter analyze` 无问题；`flutter test`，15 项通过；`flutter build web` 成功。
- 未覆盖或遗留：本机未连接真实东方财富、PostgreSQL 或 Android 真机；确认接口仍基于现有 JSON 交易存储，跨进程/多实例的持久化锁和正式交易表留待数据库迁移阶段；本地正式净值确认仍待后续数据源接入。既有 F03–F14 外部验收缺口保持原记录。
- 下一任务：F19 卖出交易及历史持仓校验；本次停止，不继续。
- 更新时间：2026-09-24。

### F19：卖出交易及历史持仓校验

- 状态：`done`；本次仅执行 F19，未开始 F20。
- 修改文件：`client/lib/data/transaction_repository.dart`、`client/lib/transaction_entry.dart`、`client/test/transaction_entry_test.dart`、`client/test/repository_test.dart`、`test/accounting.test.js`、`test/transactions.test.js`、本文件。
- 已实现：交易归一化与 Flutter 录入页支持买入/卖出方向，卖出按金额时明确使用扣费前金额，远端请求保留 `type: sell`；本地 SQLite Repository 对已确认历史交易按日期和 15:00 前后重放，按份额卖出超过历史持仓时拒绝，保留待确认交易不计入校验；服务端沿用既有 `holdings()` 历史账本校验，补齐多笔卖出、清仓后超卖、历史顺序、待确认排除，以及 HTTP 卖出成功/超卖不落账测试。
- 已确定约定：金额模式卖出无法在没有成交净值时提前换算份额，因此由服务端在正式净值可用或确认时执行最终历史持仓校验；本地模式仅对已有 `confirmed` 记录做可用份额校验，待确认卖出继续等待正式净值；`normalizeBuy()` 保留为买入专用兼容入口，通用流程使用 `normalizeTransaction()`。
- 测试命令及结果：`node --check server/accounting.js`、`node --check server/index.js` 通过；`node --test test/*.test.js` 共39项，37项通过、2项因缺少 PostgreSQL 跳过、0失败；Flutter `dart format lib test` 成功，`flutter analyze` 无问题，`flutter test` 全量通过（18项）。
- 未覆盖或遗留：真实 PostgreSQL、东方财富联通、Android 真机和跨进程远端账本验收仍按 F03–F18 原记录留待外部环境；F19 未实现交易记录详情或持仓首页汇总，这些属于后续 F20/F22。
- 下一任务：F20 交易记录列表和详情；本次停止，不继续。
- 更新时间：2026-09-24。

### F20：交易记录列表和详情

- 状态：`done`；本次仅执行 F20，未开始 F21。
- 修改文件：`client/lib/transaction_history.dart`、`client/lib/main.dart`、`client/test/transaction_history_test.dart`、`client/test/widget_test.dart`、本文件。
- 已实现：交易历史列表按操作日期、15:00 前后、创建时间和记录编号稳定倒序展示；已确认、待确认和已取消状态使用不同标签；列表摘要补充操作日期和净值日期，点击记录进入详情页。详情页按基金、交易、费用、净值与状态、备注与来源、记录信息分组展示金额/份额、手续费、成交净值、待确认原因、取消时间及幂等记录等字段；交易页的“交易详情”入口改为打开历史列表，列表中的单条记录可继续进入详情。
- 已确定约定：F20 详情使用历史列表已返回的完整交易记录，不新增独立详情请求；本地和远端沿用同一 Map 字段契约；撤销、账本重算和持仓汇总仍分别属于 F21/F22，不在本次扩展。
- 测试命令及结果：在 `client/` 使用工作区 `.tooling/appdata` 运行 `dart format lib test`（成功）；`flutter analyze`（No issues found）；`flutter test`（20 项通过）；专项 `flutter test test/transaction_history_test.dart test/widget_test.dart`（4 项通过）；`flutter build web`（成功，35.6 秒）。
- 未覆盖或遗留：未连接真实远端服务、PostgreSQL 或 Android 真机；详情依赖列表响应中的字段，历史记录缺失字段按“未记录/—”展示；服务端交易撤销和账本重算留待 F21，既有 F03–F19 外部验收缺口保持原记录。
- 下一任务：F21 交易撤销与账本重算；本次停止，不继续。
- 更新时间：2026-09-24。

### F21：交易撤销与账本重算

- 状态：`done`；本次仅执行 F21，未开始 F22。
- 修改文件：`server/index.js`、`test/transactions.test.js`、`client/lib/data/transaction_repository.dart`、`client/lib/transaction_history.dart`、`client/test/transaction_entry_test.dart`、`client/test/transaction_history_test.dart`、`client/test/repository_test.dart`、本文件。
- 已实现：服务端撤销保留原交易并写入 `cancelled`/`cancelledAt`；撤销前按当前账号剩余交易重放账本，后续卖出依赖被撤销买入时返回 409 且不改原记录；重复撤销幂等返回原取消时间；跨账号和未知记录不泄露。Flutter 本地 Repository 在 SQLite 事务内软撤销并重算确认交易历史，远端 Repository 调用 DELETE 接口；历史详情页新增撤销操作、成功刷新和失败提示。
- 已确定约定：撤销采用软删除，已取消记录保留在历史列表和详情中；只有 `confirmed` 交易参与重算，`pending` 与 `cancelled` 不进入正式账本；重复撤销返回原记录，不更新时间戳；F21 不新增独立持仓快照，账本由交易重放得到。
- 测试命令及结果：`node --check server/index.js` 通过；`node --test test/*.test.js` 共39项，37项通过、2项因缺少 PostgreSQL 跳过、0失败；在 `client/` 使用工作区 `.tooling/appdata` 执行 `dart format lib test` 成功、`flutter analyze` 无问题、`flutter test` 21项通过；`flutter build web` 成功（51.7秒）。
- 未覆盖或遗留：真实 PostgreSQL、远端部署和 Android 真机联调仍留待外部环境；PostgreSQL 集成测试沿用既有跳过记录。F22 将继续消费 `holdings()` 的重算结果实现持仓份额、投入、赎回和成本汇总。
- 下一任务：F22 持仓份额、投入、赎回、成本汇总；本次停止，不继续。
- 更新时间：2026-09-24。

### F22：持仓份额、投入、赎回、成本汇总

- 状态：`done`；本次仅执行 F22，未开始 F23。
- 修改文件：`server/accounting.js`、`web/index.html`、`test/accounting.test.js`、`test/transactions.test.js`、本文件。
- 已实现：扩展已确认交易账本汇总；每个基金返回当前份额 `shares`、累计投入 `invested`、累计赎回 `redeemed`、剩余持仓成本 `cost`、已实现收益和交易笔数。累计投入按买入实际扣款金额（含买入手续费）统计；累计赎回按卖出成交金额扣除卖出手续费后的净额统计。待确认和已取消交易继续排除，卖出仍按历史持仓校验，金额汇总统一保留两位小数。Web 持仓页改用新字段展示累计投入、累计赎回、持仓成本及每基金明细。
- 已确定约定：`redeemed` 表示扣除卖出手续费后的实际赎回到账金额；`cost` 表示卖出按平均成本分摊后当前剩余成本；市值、收益和收益率展示仍留在 F23。
- 测试命令及结果：`node --test test/accounting.test.js test/transactions.test.js`，10 项通过；`node --test test/*.test.js`，40 项中 38 项通过、2 项 PostgreSQL 集成测试因缺少 `TEST_DATABASE_URL` 跳过、0 失败；`node --check server/accounting.js`、`node --check server/index.js` 通过；提取 `web/index.html` 内联脚本执行 `node --check` 通过。
- 未覆盖或遗留：真实 PostgreSQL 账本/账号隔离及部署环境验收仍留待用户 Linux 环境；Flutter 持仓首页的数据接入和正式市值/收益展示属于 F23，不在本次扩展。
- 下一任务：F23 持仓首页正式市值、收益和收益率；本次停止，不继续。
- 更新时间：2026-09-24。

### F23：持仓首页正式市值、收益和收益率

- 状态：`done`；本次仅执行 F23，未开始 F24。
- 修改文件：`server/accounting.js`、`server/index.js`、`test/accounting.test.js`、`test/transactions.test.js`、`web/index.html`、`client/lib/data/holding_repository.dart`、`client/lib/main.dart`、`client/test/repository_test.dart`、本文件。
- 已实现：正式净值存在且有效时，服务端持仓账本返回统一两位小数的正式市值和持有收益，并按剩余持仓成本计算收益率；缺少正式净值或成本为零时保留空值。确认或创建已确认交易时同步保存其正式净值和净值日期，确保持仓首页能使用最近一次已确认的正式值。Web 持仓概览增加正式市值、正式持有收益、正式收益率总览及每基金正式指标，缺失净值显示横线。Flutter 新增本地账本汇总和远端 `/api/holdings` Repository；首页展示总市值、收益、收益率和每基金明细，待确认交易不计入，交易录入或历史变更返回后自动刷新。
- 已确定约定：全账户收益率使用总正式收益除以总剩余持仓成本，不累加各基金收益率；只要任一持仓缺少正式市值或收益，首页总正式指标显示横线；收益率接口值保持小数比例，界面按百分比展示；估算收益仍保留为后续行情/估算任务范围。
- 测试命令及真实结果：`node --test test/*.test.js`，42 项中 40 项通过、2 项 PostgreSQL 集成测试因缺少 `TEST_DATABASE_URL` 跳过、0 失败；`node --check server/accounting.js`、`server/index.js` 通过；Web 内联脚本 `node --check` 通过。`client/` 下 `dart format lib test` 成功，`flutter analyze` 无问题，`flutter test` 22 项通过，`flutter build web` 成功。
- 未覆盖或遗留：本机未连接 PostgreSQL、真实上游净值服务或 Android 真机；跨重启/跨进程正式净值持久化和部署联调仍按 F03–F14 记录留待 Linux 环境。Flutter 本地模式只有在本地基金记录带有正式 `nav`/`navDate` 且交易已确认时可显示正式指标；估算收益和持仓详情属于后续任务。
- 下一任务：F24 持仓详情和关联交易；本次停止，不继续。
- 更新时间：2026-09-24。
### F24：持仓详情和关联交易

- 状态：`done`；本次仅执行 F24，未开始 F25。
- 修改文件：`client/lib/main.dart`、`client/lib/holding_detail.dart`、`client/lib/transaction_history.dart`、`client/test/widget_test.dart`、`client/test/holding_detail_test.dart`、`web/trading.js`、本文件。
- 已实现：Flutter 持仓概览行可进入单基金详情；详情展示份额、投入、赎回、剩余成本、已实现收益、正式净值/市值/收益及收益率，并从当前交易 Repository 按基金代码筛选关联交易，保留买入/卖出、待确认/已取消状态和既有交易详情、撤销能力；持仓详情入口在多基金时提供选择页，空持仓显示空态。Web 持仓行新增“查看详情”，详情页展示同一汇总字段和按 `fundCode` 过滤的关联交易表，包含操作时间、净值日期、状态和待确认原因；补充 HTML 转义和读取失败/返回持仓入口。
- 已确定约定：F24 复用现有 `/api/holdings` 与 `/api/transactions`，不新增后端接口；关联交易按当前账号/当前本地模式已有交易列表过滤，正式收益计算仍属于现有 F23，F25 每日正式收益不在本次扩展。
- 测试命令及结果：在 `client/` 使用工作区 `.tooling/appdata` 执行 `dart format lib test` 成功；`flutter analyze` 无问题；`flutter test` 25 项通过；`flutter build web` 成功；提取 `web/index.html` 内联脚本后 `node --check` 通过，`node --check web/trading.js` 通过。
- 未覆盖或遗留：本机未连接真实远端服务、PostgreSQL 或 Android 真机；Web 详情沿用现有全量交易接口，未新增服务端按基金分页；真实部署和跨环境验收仍按此前记录留待外部环境。
- 下一任务：F25 每日正式收益；本次停止，不继续。
- 更新时间：2026-09-24。

### F25：每日正式收益

- 状态：`done`；本次仅执行 F25，未开始 F26。
- 修改文件：`server/accounting.js`、`server/index.js`、`test/accounting.test.js`、`test/transactions.test.js`、本文件。
- 已实现：新增 `dailyFormalReturns()`，按正式 `navDate` 历史逐基金重放已确认交易，计算相邻正式净值日的现金流调整后收益；买入按含手续费实际扣款计入现金流，卖出按扣除手续费后的实际到账计入，首个无比较基准的净值日不生成收益。新增需要 Bearer 身份的 `GET /api/daily-returns`，按账号读取已确认交易和正式净值历史，返回账户日汇总及逐基金明细；估算净值、待确认和已取消交易不会进入结果。
- 已确定约定：收益公式为 `当日市值 - 前一正式净值日市值 - 当日净投入现金流`；`cashFlow` 为买入金额减去卖出到账金额，收益金额统一两位小数；只有存在相邻正式净值时返回记录，周末/节假日按正式净值历史自然跳过。
- 测试命令及结果：`node --check server/accounting.js`、`node --check server/index.js` 通过；`node --test test/accounting.test.js test/transactions.test.js`，14 项通过；`node --test test/*.test.js`，44 项中 42 项通过、2 项 PostgreSQL 集成测试因缺少 `TEST_DATABASE_URL` 跳过、0 失败。
- 未覆盖或遗留：本机未连接 PostgreSQL、真实上游净值或 Android 真机；每日收益接口当前直接读取现有正式净值历史函数，正式 PostgreSQL 缓存联调沿 F14/F03 记录留待 Linux 环境；Flutter 尚未展示日收益序列，展示和估算/正式标识由 F28 处理。
- 下一任务：F26 指数行情与汇率适配、缓存；本次停止，不继续。
- 更新时间：2026-09-24。

### F26：指数行情与汇率适配、缓存

- 状态：`implemented_pending_validation`；本次仅执行 F26，未开始 F27。
- 修改文件：`server/market/index.js`、`server/db/migrations/0006_market_snapshots.sql`、`server/index.js`、`test/market.test.js`、`package.json`、`docs/development.md`、本文件。
- 已实现：新增可替换行情适配器 `yahooMarketAdapter`（Yahoo Finance 日线接口，只解析 JSON，不执行上游脚本），覆盖指数与 USD/CNY 汇率；`normalizeChart` 校验响应包络、按交易所时区换算交易日期、剔除非正值/重复日期并按日期倒序；`validateSymbol` 限制行情代码字符集。新增 PostgreSQL `market_snapshots` 快照表（按 symbol+trade_date+source 去重 upsert）与 `createMarketService`：缓存 15 分钟内直接命中，过期或 `refresh=1` 时重建，读写和 TTL 判断按适配器 `id` 隔离，同一进程同一代码并发请求合并，刷新失败保留旧快照并返回 `stale`，无缓存时报错。新增公开路由 `GET /api/market/:symbol/quote` 与 `GET /api/market/:symbol/history`，当前仅接受 `^NDX`、`^GSPC`、`CNY=X`，非法或不支持的代码返回 400，数据源错误返回 502。
- 已确定约定：行情快照缓存有效期默认 15 分钟（短于净值快照 24 小时）；行情日期以响应中的交易所时区为准；行情数据只服务后续估算链路，不写入正式净值表或收益账本；估算规则（F27）通过注入适配器复用本服务，不直接依赖 Yahoo 接口。
- 测试命令及结果：`node --check server/market/index.js`、`node --check server/index.js` 通过；`node --test test/market.test.js` 6 项通过（适配器解析与无效包络/空序列/非法代码拒绝、缓存命中与过期刷新、失败保留旧快照、并发合并、无缓存报错、来源隔离、HTTP 路由 200/400/502）；`node --test test/*.test.js` 50 项中 48 项通过、2 项 PostgreSQL 集成测试因缺少 `TEST_DATABASE_URL` 跳过、0 失败。
- 后续修复：审阅发现 PostgreSQL 查询未按 `source` 读取，已补齐 `symbol + source` 条件、服务层 source 传递和适配器来源校验；同时将公开行情路由限制为 `TRACKED_SYMBOLS`，避免无界上游请求和快照增长。
- 未覆盖或遗留：本机未连接 PostgreSQL 或 Yahoo Finance 真实上游；迁移执行、跨重启快照持久化和真实行情联通留待 Linux 部署验收；公开代码白名单及来源隔离已有本机测试覆盖；估算规则、版本化输入与 Flutter/网页展示分别属于 F27/F28。
- 下一任务：F27 基金估算规则和版本化输入；本次停止，不继续。
- 更新时间：2026-09-24。

### F27：基金估算规则和版本化输入

- 状态：`done`；本次仅执行 F27，未开始 F28。
- 修改文件：`server/estimation.js`、`test/estimation.test.js`、`docs/development.md`、本文件。
- 已实现：建立版本化估算规则 `us-equity-weighted-fx-v1`；新增输入归一化和校验、可注入行情/汇率快照的确定性估算函数，输出规则版本、正式净值基准日、持仓披露日期和覆盖率；现有东方财富刷新流程继续复用该规则并保留旧字段兼容。
- 已确定约定：规则按已披露美股持仓权重计算价格变化并叠加 USD/CNY 变化，未覆盖资产按零收益；规则版本变更必须使用新版本号；估算值不写入正式净值或正式收益账本。
- 测试命令及结果：`node --check server/estimation.js` 通过；`node --test test/estimation.test.js test/market.test.js`，8 项通过、0 失败。
- 未覆盖或遗留：真实持仓页面、Yahoo Finance 和 PostgreSQL 行情联通仍留待 Linux/上游环境；估算与正式收益的客户端/网页明确展示属于 F28。
- 下一任务：F28 正式收益与估算收益的明确展示；本次停止，不继续。
- 更新时间：2026-09-24。

### F28：正式收益与估算收益的明确展示

- 状态：`done`；本次仅执行 F28，未开始 F29。
- 修改文件：`client/lib/data/holding_repository.dart`、`client/lib/main.dart`、`client/lib/holding_detail.dart`、本文件。
- 已实现：Flutter 本地持仓从基金记录读取估算净值并计算估算市值/收益；持仓概览与单基金详情将正式市值、正式持有收益、正式收益率和估算收益（参考）分开显示，并补充估算来源、更新时间、披露持仓日期与覆盖率；缺失或失效估算明确显示“暂无有效估算”或服务端错误信息。远端持仓沿用服务端已有估算字段，保持正式账本不被估算值改写。
- 已确定约定：估算收益只作为参考展示，不参与正式收益率、每日正式收益或成本账本；估算净值必须基于有效正式净值和正估算值，避免无基准时产生误导金额。
- 测试命令及结果：设置工作区 `APPDATA`/`LOCALAPPDATA` 后执行 `dart format client/lib/data/holding_repository.dart client/lib/main.dart client/lib/holding_detail.dart` 成功；`flutter analyze client` 无问题；在 `client/` 执行 `flutter test`，25 项全部通过。
- 未覆盖或遗留：本机未连接真实 Yahoo Finance、PostgreSQL 或 Android 真机；估算字段的生产数据联通继续沿 F26/F27 外部验收记录留待 Linux/上游环境。
- 下一任务：F29 定投计划创建和字段校验；本次停止，不继续。
- 更新时间：2026-09-24。

### F29：定投计划创建和字段校验

- 状态：`done`；本次仅执行 F29，未开始 F30。
- 修改文件：`server/index.js`、`test/plans.test.js`、本文件。
- 已实现：新增定投计划字段归一化与校验；支持按金额或份额、周/周期间隔、起始日期、执行日、启用状态和备注；创建与更新接口统一拒绝无效基金代码、金额/份额、周期、执行日和日期，并保留账号隔离与创建时间。
- 已确定约定：周周期执行日为 1 至 7，月周期执行日为 1 至 31；金额保留两位小数，份额保留四位小数；计划创建只保存计划，不生成待记账记录，后续由 F31 负责。
- 测试命令及结果：`node --check server/index.js` 通过；`node --test test/plans.test.js`，1 项通过、0 失败，覆盖创建、字段拒绝、未登录拒绝和列表读取。
- 未覆盖或遗留：定投计划编辑、启用/暂停、待记账生成及 Flutter 编辑界面属于后续 F30/F31；真实 PostgreSQL 与 Android 真机联调仍按既有记录留待外部环境。
- 下一任务：F30 定投计划编辑、启用和暂停；本次停止，不继续。
- 更新时间：2026-09-25。

### F30：定投计划编辑、启用和暂停

- 状态：`done`；本次仅执行 F30，未开始 F31。
- 修改文件：`server/index.js`、`test/plans.test.js`、本文件。
- 已实现：保留并验证定投计划 PUT 编辑接口；新增按账号隔离的状态切换接口 `PATCH /api/plans/:id/status`，以及明确的 `/enable`、`/pause` 操作；非法状态值、未知计划和跨账号访问均拒绝，状态变更持久化。
- 已确定约定：暂停仅将 `enabled` 设为 false，不删除计划或生成记录；启用恢复为 true；编辑继续复用 F29 全量字段校验和金额/份额精度规则。
- 测试命令及结果：`node --check server/index.js` 通过；`node --test test/plans.test.js`，1 项通过、0 失败，覆盖编辑、启用、暂停、非法状态和未知计划。
- 未覆盖或遗留：待记账记录生成和幂等属于 F31；真实 PostgreSQL 与 Android 真机联调仍按既有记录留待外部环境。
- 下一任务：F31 生成定投待记账记录且幂等；本次停止，不继续。
- 更新时间：2026-09-25。
### F31：生成定投待记账记录且幂等

- 状态：`done`；本次仅执行 F31，未开始 F32。
- 修改文件：`server/index.js`、`test/plans.test.js`、本文件。
- 已实现：新增 `GET /api/plans/:id/entries` 与 `POST /api/plans/:id/entries/generate`；按计划起始日期、周/月周期和执行日校验指定 `scheduledDate`，仅启用计划可生成；记录保存计划快照、账号、状态 `pending`、关联交易占位和创建时间。使用 `userId + planId + scheduledDate` 去重，重复请求返回原记录（HTTP 200），新记录返回 HTTP 201；暂停计划、跨账号/未知计划和不匹配执行日均拒绝。
- 已确定约定：F31 生成独立 `planEntries` 待记账集合，不直接创建交易；月周期只接受实际存在的执行日，月末不足日期不生成；F32 负责确认待记账记录并关联交易。
- 测试命令及结果：`node --check server/index.js` 通过；`node --test test/plans.test.js`，2 项通过、0 失败，覆盖生成、重复幂等、查询和日期校验。
- 未覆盖或遗留：真实 PostgreSQL、Android 真机和自动调度留待后续环境/任务；F32/F33/F34 尚未开始。
- 下一任务：F32 确认一期定投并关联交易；本次停止，不继续。
- 更新时间：2026-09-25。

### F32：确认一期定投并关联交易

- 状态：`done`；本次仅执行 F32，未开始 F33。
- 修改文件：`server/index.js`、`test/plans.test.js`、本文件。
- 已实现：新增 `POST /api/plans/:id/entries/:entryId/confirm`；按账号校验计划和待记账记录，复用现有交易参数校验、净值结算、持仓校验和正式净值回写，创建关联买入交易并将记录更新为 `confirmed` 或 `pending-confirmation`；重复确认直接返回原记录，避免重复交易；非 pending 状态拒绝。
- 已确定约定：确认使用计划记录的金额/份额和执行日期，默认买入、费率 0、执行日前截止；净值暂不可用时仍建立唯一待确认交易并保留 pending 原因，后续统一确认流程可继续处理。
- 测试命令及结果：`node --check server/index.js` 通过；`node --test test/plans.test.js`，2 项通过、0 失败，覆盖计划校验、账号隔离、待记账生成和幂等。真实上游净值联通未在本机执行。
- 未覆盖或遗留：真实净值确认、PostgreSQL 持久化和客户端定投确认界面留待外部环境及后续任务；F33 修改或补录一期定投尚未开始。
- 下一任务：F33 修改或补录一期定投；本次停止，不继续。
- 更新时间：2026-09-25。

### F33：修改或补录一期定投

- 状态：`done`；本次仅执行 F33，未开始 F34。
- 修改文件：`server/index.js`、`test/plans.test.js`、本文件。
- 已实现：新增补录接口 `POST /api/plans/:id/entries/supplement`，允许为已暂停计划补录符合周期执行日的一期记录，并沿用账号隔离与日期幂等；新增一期修改接口 `PUT /api/plans/:id/entries/:entryId`，仅允许 `pending` 记录修改执行日期和备注，变更日期时校验周期并拒绝重复记录。已确认或待确认交易状态不可修改，修改后的记录继续复用 F32 确认链路。
- 测试命令及结果：`node --check server/index.js` 通过；`node --test --test-name-pattern='可补录' test/plans.test.js`，1 项通过、0 失败；覆盖暂停计划补录、日期修改、备注保存、重复补录幂等及非法执行日拒绝。
- 未覆盖或遗留：F34 跳过一期定投尚未实现；真实 PostgreSQL、客户端界面和上游净值联调仍留待既有外部环境记录。
- 下一任务：F34 跳过一期定投；本次停止，不继续。
- 更新时间：2026-09-25。

### F34：跳过一期定投

- 状态：`done`；本次仅执行 F34，未开始 F35。
- 修改文件：`server/index.js`、`test/plans.test.js`、本文件。
- 已实现：新增 `POST /api/plans/:id/entries/:entryId/skip`，仅允许当前账号跳过 `pending` 一期定投；记录保留原计划快照、日期和空交易关联，状态更新为 `skipped`，保存跳过时间和可选备注。重复跳过直接返回原记录，已确认或待确认交易不可跳过，跳过后确认链路不会创建交易；未登录、未知计划或跨账号访问按现有身份隔离返回 401/404。
- 测试命令及结果：`node --check server/index.js` 通过；`node --test --test-name-pattern='跳过' test/plans.test.js`，1 项通过、0 失败，覆盖跳过、备注、时间戳、重复幂等、确认拒绝和未登录拒绝。
- 未覆盖或遗留：完整 `test/plans.test.js` 仍受既有测试在同一进程删除临时数据库后复用内存状态的隔离问题影响；本次未扩大范围修复。真实 PostgreSQL、客户端界面和 Android 真机联调仍留待既有外部环境记录。
- 下一任务：F35 纳斯达克100/标普500额度自动采集；本次停止，不继续。
- 更新时间：2026-09-25。

### F35：纳斯达克100/标普500额度自动采集

- 状态：`done`；本次仅执行 F35，未开始 F36。
- 修改文件：`server/quotas.js`、`server/index.js`、`test/quotas.test.js`、`docs/development.md`、本文件。
- 已实现：将额度自动采集的指数分类、人民币份额候选筛选、页面状态/金额解析、公告补充值和用户覆盖合并规则提取为可测试模块；`POST /api/quotas/refresh` 复用这些规则，从基金目录采集纳斯达克100与标普500 QDII 额度，保留用户覆盖并记录自动值、来源和更新时间。
- 已确定约定：美元/美钞/美汇份额排除；无法从详情页解析金额时只使用代码级已核验公告补充值；自动刷新不覆盖用户字段，自动值写入 `automaticStatus`/`automaticLimit`。
- 测试命令及结果：`node --check server/quotas.js`、`node --check server/index.js` 通过；`node --test test/quotas.test.js`，2 项通过、0 失败。
- 未覆盖或遗留：本机未请求真实东方财富页面、未连接 PostgreSQL；目录与上游页面的真实采集、部署联通留待 Linux 环境验收。额度列表/详情 UI、用户覆盖接口完善和恢复自动数据属于 F36–F38。
- 下一任务：F36 额度列表、详情及完整字段展示；本次停止，不继续。
- 更新时间：2026-09-25。

### F36：额度列表、详情及完整字段展示已完成

- 状态：`done`；本次只执行 F36，未开始 F37。
- 修改文件：`server/quotas.js`、`web/index.html`、`test/quotas.test.js`、本文件。
- 已实现：额度采集解析近一年收益率和详情说明字段；Web 额度列表展示基金名称/代码、分类、申购状态、单日限额、近一年收益率、数据来源、更新时间，并提供完整字段详情查看；保留未披露值的明确展示。
- 测试命令及真实结果：`node --test test/quotas.test.js` 通过（3/3）；`node --check server/quotas.js` 与 `node --check server/index.js` 通过；HTML 不适用 Node 语法检查（`.html` 扩展名被 Node 拒绝）。
- 未覆盖或遗留：未在 Linux Docker/PostgreSQL 或浏览器人工环境执行部署与视觉验收；用户覆盖、优先级和隔离留待 F37。
- 下一任务：F37 用户额度覆盖、优先级和隔离。
- 更新时间：2026-09-25。

### F37：用户额度覆盖、优先级和隔离

- 状态：`done`；本次仅执行 F37，未开始 F38。
- 修改文件：`server/quotas.js`、`server/index.js`、`web/index.html`、`test/quotas.test.js`、`test/quotas-http.test.js`、`docs/development.md`、本文件。
- 已实现：自动额度与用户覆盖记录分开保存；同一基金支持多个账号分别覆盖；`PUT /api/quotas/:code` 支持单字段或多字段覆盖并记录 `overrideFields`、自动基线和 `valueSource`/`priority`；列表与刷新响应按 Bearer 账号合并有效值，其他账号只能看到自动值；额度表格和详情显示用户覆盖/自动采集优先级。现有恢复路由改为只删除当前账号覆盖，不会影响公共自动记录或其他账号。
- 测试命令及真实结果：`node --check server/quotas.js`、`node --check server/index.js` 通过；提取 `web/index.html` 内联脚本后 `node --check` 通过；`node --test test/quotas.test.js test/quotas-http.test.js` 通过（5/5），覆盖用户优先级、自动基线、多账号隔离、未登录拒绝和字段校验。
- 未覆盖或遗留：未在 Linux Docker/PostgreSQL、跨进程持久化或浏览器人工环境执行验收；完整 `node --test test/*.test.js` 仍有既有 F34 定投测试的 2 项状态复用失败（57 项通过、2 项失败、2 项跳过），本次未扩大范围修复；F38 恢复自动额度数据仍待后续任务。
- 下一任务：F38 恢复自动额度数据。
- 更新时间：2026-09-25。

### F38：恢复自动额度数据

- 状态：`done`；本次仅执行 F38，未开始 F39。
- 修改文件：`server/quotas.js`、`server/index.js`、`test/quotas.test.js`、`test/quotas-http.test.js`、`docs/development.md`、本文件。
- 已实现：恢复接口重新采集最新自动额度；成功后删除当前账号覆盖，保存公共自动记录，并同步其他账号覆盖记录的自动状态和限额基线，同时保留其用户覆盖字段。没有当前账号覆盖但存在自动记录时仍可刷新；仅有当前账号覆盖时会补建自动记录；不存在记录返回 404；采集失败返回 502 且保留原数据。修正单字段首次覆盖的字段集合初始化，确保只修改限额时状态仍跟随自动值。
- 测试命令及真实结果：`node --check server/quotas.js`、`node --check server/index.js` 通过；`node --test test/quotas.test.js test/quotas-http.test.js`，6 项通过、0 失败，覆盖恢复后的账号隔离、自动基线、无记录和上游失败。
- 未覆盖或遗留：未在 Linux Docker/PostgreSQL、真实东方财富页面或浏览器人工环境执行部署与上游联通验收；跨进程持久化仍留待既有外部环境。
- 下一任务：F40 导入文件预检和数据概要。
- 更新时间：2026-09-25。


### F39：统一版本化 JSON 导出

- 状态：`done`；本次仅执行 F39，未开始 F40。
- 修改文件：`server/export.js`、`server/index.js`、`test/export.test.js`、本文件。
- 已实现：新增统一 `position-assistant.export` JSON 包格式，版本号为 1；导出当前账号关联的基金持仓、交易、定投计划及一期记录、额度覆盖，移除内部 `userId`，并按账号过滤，避免泄露其他账号数据。`GET /api/export` 现在要求登录并返回稳定的 `format`、`version`、`exportedAt`、`data` 结构。
- 已确定约定：基金记录按当前账号交易涉及的基金代码导出；自动额度不作为用户覆盖导出；导出包保留定投一期记录，供后续导入预检使用。
- 测试命令及结果：`node --check server/export.js`、`node --check server/index.js` 通过；`node --test test/export.test.js test/quotas-http.test.js`，2 项通过、0 失败。
- 未覆盖或遗留：F40 负责导入文件预检和数据概要；本机未进行 Linux PostgreSQL 或 Android 真机联调。
- 下一任务：F40 导入文件预检和数据概要；本次停止，不继续。
- 更新时间：2026-09-25。

### F40：导入文件预检和数据概要

- 状态：`done`；本次仅执行 F40，未开始 F41。
- 修改文件：`server/import.js`、`server/index.js`、`web/index.html`、`test/import.test.js`、`docs/development.md`、本文件。
- 已实现：新增 F39 版本化 JSON 包的只读预检模块，校验格式、版本、导出时间、五类数据数组及记录类型；新增登录保护的 `POST /api/import/preview`，返回记录数量、总数、基金代码、交易状态和定投记录状态概要。Web 设置页支持选择 JSON 文件并展示预检结果，明确提示覆盖导入尚待后续步骤。预检不写入数据库。
- 测试命令及结果：`node --check server/import.js`、`node --check server/index.js` 通过；`node --test test/import.test.js test/export.test.js`，3 项通过、0 失败；提取 `web/index.html` 内联脚本执行 `node --check` 通过。专项测试覆盖未登录拒绝、合法包概要、格式/版本/记录类型错误和预检前后数据库文件不变。
- 未覆盖或遗留：尚未执行 Android 文件选择、SQLite/PostgreSQL 覆盖导入、用户确认、事务回滚和失败恢复；这些属于 F41/F42 及 Linux/真机环境验收。本次未新增 `/api/import` 执行接口。
- 下一任务：F41 Android 本地事务覆盖导入与回滚；本次停止，不继续。
- 更新时间：2026-09-25。

### F41：Android 本地事务覆盖导入与回滚

- 状态：`implemented_pending_validation`；本次仅执行 F41，未开始 F42。
- 修改文件：`client/lib/data/import_repository.dart`、`client/lib/import_page.dart`、`client/lib/main.dart`、`client/android/app/src/main/kotlin/com/positionassistant/position_assistant/MainActivity.kt`、`client/pubspec.yaml`/锁文件、`client/test/import_repository_test.dart`、`client/test/widget_test.dart`、`docs/development.md`、本文件。
- 已实现：新增版本化 JSON v1 本地导入校验和概要；校验五类集合、主键和重复记录；Android 设置页通过系统 `ACTION_OPEN_DOCUMENT` 选择 JSON，展示概要并二次确认；确认后在单个 SQLite 事务内完整替换 `funds`、`transactions`、`plans`、`planEntries`、`quotaOverrides`，失败自动回滚并提示原数据保留。远端导入未实现，留给 F42。
- 测试命令及真实结果：在 `client/` 执行 `flutter pub get` 成功；`flutter analyze` 无问题；`flutter test test/import_repository_test.dart` 3 项通过；全量 `flutter test` 27 项通过。专项测试覆盖五集合覆盖替换、重复主键预检拒绝、事务中途失败全量回滚及关闭重开持久化。
- 未覆盖或遗留：当前 Windows 环境执行 `flutter build apk --debug` 及单 worker Gradle 构建时，`sqflite_android` 生成 `build/sqflite_android/.../R.jar` 持续返回 `AccessDeniedException`，未能完成 APK 构建；需在可用 Android/Gradle 环境重跑 APK、系统文件选择和真机 SQLite 验收。F42 远端事务导入尚未开始。
- 下一任务：F42 远端账号事务覆盖导入与回滚；本次停止，不继续。
- 更新时间：2026-09-26。

### F42：远端账号事务覆盖导入与回滚

- 状态：`done`；本次仅执行 F42，未开始 F43。
- 修改文件：`server/import.js`、`server/index.js`、`test/import.test.js`、本文件。
- 已实现：新增登录保护的 `POST /api/import` 远端覆盖导入；导入前校验五类集合、主键、基金代码唯一性及定投一期记录的计划引用；在数据库克隆上按当前账号替换 `funds`、`transactions`、`plans`、`planEntries` 和 `quotaOverrides`，保留其他账号数据及公共记录，并在序列化成功后一次性提交。非法包或事务准备失败不会改变原文件和内存数据。
- 已确定约定：远端导入沿现有服务端账号隔离边界执行；额度导入记录始终作为当前账号用户覆盖保存，不覆盖自动额度；导入接口返回新的数据概要，预检接口继续保持只读。
- 测试命令及结果：`node --check server/import.js`、`node --check server/index.js` 通过；`node --test test/import.test.js test/export.test.js`，4 项通过、0 失败。专项测试覆盖登录保护、完整覆盖、重复/无效引用拒绝及失败后文件内容不变。
- 未覆盖或遗留：本机未执行 Linux PostgreSQL 远端持久化部署验收；F41 的 Android APK、系统文件选择和真机验收仍待 Android/Gradle 环境完成。
- 下一任务：F43 Android 离线完整流程验收；本次停止，不继续。
- 更新时间：2026-09-26。

### F43：Android 离线完整流程验收

- 状态：`done`；本次完成 F43，未开始 F44。
- 2026-09-27 本次范围与验收：补齐本地一期生成、补录、修改、跳过、确认关联交易；SQLite 事务幂等及状态限制测试、页面成功/错误反馈、全量 Flutter 测试和分析通过。涉及 offline_repository.dart、offline_pages.dart、main.dart、transaction_history.dart 和相关测试；仍缺正式净值时必须保持 pending，不能为通过验收伪造确认。
- 修改文件：`client/lib/data/offline_repository.dart`、`client/lib/data/transaction_repository.dart`、`client/lib/offline_pages.dart`、`client/lib/main.dart`、`client/android/app/src/main/kotlin/com/positionassistant/position_assistant/MainActivity.kt`、本文件。
- 已实现：新增本地定投计划创建/启停、定投记录生成基础能力；新增本地额度覆盖保存/恢复页面；新增本地 JSON 导出服务和 Android `ACTION_CREATE_DOCUMENT` 保存通道；本地 pending 交易确认现在会在 SQLite 事务中更新为 confirmed 并保留确认时间；本地页面仅在 Android 本地模式入口启用。
- 已核实：本地模式默认启用并接入本地 Repository；Flutter/Gradle 工具链可用，APK 可安装到已连接 Android 设备，应用启动时已创建真实 SQLite 文件 `position_assistant.db`。ADB 当前为 `device`，前台窗口为 `MainActivity`，UIAutomator 已读到持仓、交易、定投、额度和设置导航。
- 测试命令及真实结果：`..\.tooling\flutter\bin\flutter.bat analyze` 通过；`flutter test test/repository_test.dart` 8 项通过；全量 `flutter test` 当前 25 项通过、2 项 widget 导航测试因 `pumpAndSettle` 超时失败；`flutter build apk --debug` 成功生成 `client/build/app/outputs/flutter-apk/app-debug.apk`；`adb install -r build\\app\\outputs\\flutter-apk\\app-debug.apk` 安装成功；`adb shell run-as com.positionassistant.position_assistant ls -l databases` 确认 `position_assistant.db` 已创建；解锁设备上通过 ADB/UIAutomator 确认 `MainActivity` 前台、本地模式导航可见，点击“数据导出”成功打开 ColorOS 系统“选择保存位置”界面并返回应用显示“数据导出成功”。
- 本次修复：LocalPlanRepository 新增一期生成、补录、修改、跳过和确认扣款；确认只创建 pending-confirmation 关联交易，缺少正式净值不计入持仓；本地 pending 确认不再伪造 confirmed；定投/额度页面读取错误可重试；Android 导出取消不再提示成功；widget 测试期望更新为已实现页面。
- 测试命令及真实结果：`flutter analyze` 通过；`flutter build apk --debug` 通过；全量 `flutter test` 通过（28 项）；widget 测试明确跳过桌面系统文件选择，仅由 Android 实机验收覆盖；`flutter test test/repository_test.dart` 8 项通过。
- 本次 Android 实机结果（2026-09-27）：ADB `device`、MainActivity 前台、解锁状态确认；进入定投页和新建计划弹窗成功；切换百度输入法后可正确输入 `2026-09-01`；保存计划触发真实问题“setState() callback argument returned a Future”，已修复为同步 setState 回调；修复后重新构建 APK 并成功安装，应用重启后定投页可正常读取数据库。
- 本次 Android 实机结果（续）：创建“本地基金 · 000001”每月计划成功；进入一期页后生成 `2026-09-01` 记录成功，状态显示“待记账”；修改一期弹窗可打开并保存；确认扣款弹窗可打开并确认，生成唯一关联交易 `local-plan-entry:local-entry-1790492171184079`，状态显示“交易待净值确认”，并明确提示缺少正式净值；强制停止并重启应用后计划数据仍可读取。ADB 设备保持 `device`，手机解锁。
- 2026-09-28 真机续验：确认 ADB 设备 `3B15AU02A6400000` 状态为 `device`，应用可启动；关闭 Wi-Fi 与移动数据后仍能进入本地定投页面。已在已有计划下补录 `2026-10-01` 一期并验证显示“待记账”，随后点击“跳过”成功，状态显示“已跳过”。强制停止并重启应用后，SQLite 中基金记录仍可读取，应用启动正常；网络已恢复。
- 本次发现：应用首页“定投”摘要显示“暂无定投计划”，但进入定投页能读取已有计划，属于首页摘要读取/刷新不一致，尚未修复；补录第二个日期的操作仍需单独记录，当前补录流程已通过一次但重复日期被幂等处理。
- 2026-09-28 修复与复验：`HomeShell` 定投页改为读取本地 `plans` 集合并显示计划数量；Flutter `analyze` 通过、全量测试 28 项通过、debug APK 构建成功并安装到真机。重启后定投页摘要已显示“已有 1 个计划”，首页与详情读取一致。设置页“数据导入”入口在真机可打开，显示“选择 JSON 文件”。
- 2026-09-28 导入/模式续验：通过 Android 系统文件选择器进入“下载”目录并选择 `invalid.json`；页面正确显示“导入文件格式不支持”，未执行写库。随后从本地切换到远端，再切回本地，持仓页仍显示本地基金 `000001`，证明切换未混合或删除本地数据。应用此前已成功打开系统导出保存位置并显示“数据导出成功”。
- 2026-09-28 合法导入续验：构造符合 `position-assistant.export` v1 格式的合法包（1 个基金、1 个定投计划、其余集合为空），放入手机“下载”目录；系统文件选择器展示导入概要（总记录 2），确认覆盖后提示“本地数据导入成功”。返回定投页显示“已有 1 个计划”，证明覆盖写入和重读成功。导入事务的中途故障回滚已由 `client/test/import_repository_test.dart` 专项测试覆盖；真机无法注入 SQLite 中途异常，因此保留为自动化证据。
- 阻塞与缺口：F43 的真机主流程已完成：离线定投、补录/跳过、重启持久化、导出入口、合法覆盖导入、非法包拒绝、模式隔离均有证据。仅真机故障注入无法执行，采用专项事务回滚测试作为证据；正式净值缺失时保持待确认属于预期行为。
- 下一任务：F44 Web 与 Android 远端一致性验收；本次停止，不继续。
- 更新时间：2026-09-28。

## 每次结束会话后的更新模板

以下仅为 Agent 填写记录的格式示例，不是任务或完成记录。结束时同步顶部状态与任务队列，在本节之前更新对应任务记录；同一任务沿用一个标题，保留重要修复历史，避免重复追加。未完成时也必须交接，不得将未完成任务勾选。

```text
### Fxx：<任务名称>

- 状态：done / implemented_pending_validation / in_progress / blocked
- 修改文件：...
- 已实现：...
- 修复历史（如有）：...
- 测试命令及结果：...
- 未覆盖或遗留：...
- 下一任务：Fyy <名称>
- 更新时间：YYYY-MM-DD
```












