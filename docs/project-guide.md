# PositionAssistant 开发与维护指南

本文档是当前项目运行方式、架构边界、数据不变量和验收命令的汇总。它替代旧的开发说明和交接台账；历史任务编号和会话日志不再作为维护入口。

## 1. 项目地图

| 目录 | 当前职责 |
| --- | --- |
| `server/` | Express 服务。默认端口 `3000`。账号、交易、定投和部分原型数据仍写入 `data/db.json`。 |
| `server/db/` | PostgreSQL 迁移执行器和迁移文件。目录、正式净值、行情等公共缓存使用 PostgreSQL。 |
| `client/` | Flutter Android/Web 客户端。Android 本地模式使用 SQLite，远端模式访问 Express。 |
| `quota-service/` | 独立额度服务。默认端口 `4100`，数据文件为 `quota-service/data/db.json`，不与主服务共享运行时数据库。 |
| `web/` | 早期 Web 原型，仅用于兼容和参考。 |
| `scripts/` | 迁移、额度同步和 APK 打包脚本。 |
| `test/`、`client/test/` | Node.js 与 Flutter 测试。 |

`functions.md` 是历史产品方案。它可以帮助理解原始目标，但其中的架构和完成状态可能落后于代码；遇到冲突时，以代码、测试和本文档为准。

## 2. Node.js 与 PostgreSQL

项目使用 Node.js 22.9+（建议 Node.js 22 LTS 或更高版本）。首次准备依赖：

```bash
npm ci
```

启动主服务：

```bash
npm start
# 或：node --env-file-if-exists=.env server/index.js
```

主服务默认监听 `http://localhost:3000`。额度服务单独启动：

```bash
npm run start:quota
```

额度服务默认监听 `http://localhost:4100`；生产或 Android 包使用的地址通过 `QUOTA_SERVICE_URL` 注入，不能假设手机可以访问自身的 `127.0.0.1`。

### 本地 PostgreSQL

需要 Docker Engine 和 Docker Compose v2。首次使用时复制 `.env.example` 为 `.env`，设置非空的 `POSTGRES_PASSWORD`，然后执行：

```bash
docker compose config --quiet
docker compose up -d --wait --wait-timeout 120
docker compose ps
npm run db:migrate
```

Compose 只把 PostgreSQL 绑定到 `127.0.0.1:5432`（端口可由 `POSTGRES_PORT` 修改），数据保存在命名卷 `postgres_data`。`docker compose down` 会保留卷；`docker compose down -v` 会删除全部开发库数据，只能在明确需要重置时使用。修改 `.env` 不会改变已有卷中初始化的数据库、用户或密码，不要用删卷解决有价值数据的连接问题。

迁移脚本读取 `DATABASE_URL`，或读取 `POSTGRES_HOST`、`POSTGRES_PORT`、`POSTGRES_DB`、`POSTGRES_USER`、`POSTGRES_PASSWORD`。迁移记录保存在 `public.schema_migrations`。

迁移文件位于 `server/db/migrations/`，命名为四位递增编号，例如 `0007_description.sql`。已执行文件不可修改、删除、重命名或插入旧编号；修正必须新增迁移。迁移 SQL 应能在执行器事务内运行，不得自行控制事务，也不得包含事务外 DDL 或外部副作用。

## 3. 命令索引

`package.json` 当前脚本如下：

```text
npm start                            启动主服务
npm run start:quota                  启动额度服务
npm run db:migrate                   应用 PostgreSQL 迁移
npm run test:migrations              迁移执行器单元测试
npm run test:migrations:integration  真实 PostgreSQL 迁移集成测试
npm run test:catalog                 基金目录与搜索测试
npm run test:catalog:integration     基金目录 PostgreSQL 集成测试
npm run test:nav                     正式净值测试
npm run test:market                  行情与汇率缓存测试
npm run quota:seed                   生成额度初始数据
npm run quota:seed:check             校验额度初始数据
npm run test:quota-service           额度服务测试
```

需要数据库的集成测试使用独立的 `TEST_DATABASE_URL`，不要指向生产库。未配置时，测试应明确显示跳过，而不是伪造通过。

## 4. Flutter、数据模式与 APK

仓库自带 Flutter SDK：`.tooling/flutter/bin/flutter.bat`，Android SDK 使用 `C:\lib`（`client/android/local.properties` 已配置）。在 `client/` 目录执行：

```powershell
..\.tooling\flutter\bin\flutter.bat pub get
..\.tooling\flutter\bin\flutter.bat analyze
..\.tooling\flutter\bin\flutter.bat test
```

客户端有两种互相隔离的数据模式：

- Android 本地模式使用应用私有 SQLite。`client/lib/data/nav_repository.dart` 直接请求东方财富历史净值接口，并将快照写入 `navSnapshots`；分页读取历史记录后，选择首个不早于交易日期和截止时间的净值。无法取得正式净值时，交易保持待确认。
- 远端模式访问主服务 API。账号、交易、定投、额度覆盖和导入导出必须按账号隔离；本地与远端切换不自动合并或删除数据。

APK 必须从仓库根目录使用 `scripts\build-apk.bat`：

```powershell
scripts\build-apk.bat              # release，普通包
scripts\build-apk.bat debug        # debug，普通包
scripts\build-apk.bat with-quota   # release，内置最新额度数据
```

普通包输出为 `client\build\app\outputs\flutter-apk\持仓助手.apk`；`with-quota` 输出为 `持仓助手-带额度.apk`。两种产物应共存，脚本只清理本次同名旧文件和 Flutter 重复输出。脚本会注入额度服务地址；不要改为在 `client/` 直接运行 `flutter build apk`，也不要使用 `flutter clean` 破坏 Gradle 增量缓存。当前 release 使用默认 debug 签名，只适合安装验收，不能直接上架。

## 5. 架构与数据不变量

- Express 原型和 Flutter 客户端并存。不要把 `data/db.json` 的原型数据误认为已经迁移到 PostgreSQL。
- PostgreSQL 缓存通过可替换适配器接入。目录、净值、行情和汇率快照必须保留适配器标识、来源 URL、采集时间和 stale/错误信息；解析协议变化时使用新的适配器标识。
- 用户数据必须带账号边界。服务端接口覆盖未登录、越权、重复请求和上游失败；批量导入在事务中完整替换，失败时回滚。
- 交易是持仓账本的事实来源。待确认或已取消交易不进入正式持仓收益；估算收益不能写入正式收益账本。
- 定投计划生成待记账记录，确认、补录和跳过必须保持幂等，不假设销售平台一定扣款成功。
- 额度自动采集和用户覆盖分开保存；用户覆盖只影响当前账号，删除覆盖后才能回到自动值。
- 本地 SQLite 的业务数据与远端账号数据保持独立，导入导出使用版本化 JSON 格式。

## 6. 验证规则

根据改动范围执行最小充分检查：

- JavaScript：对变更文件运行 `node --check`，再运行对应 `npm run test:*`；涉及数据库时补充迁移或目录集成测试。
- Flutter：运行 `flutter analyze` 和相关 `flutter test`；导入、SQLite、模式切换或 Android 文件选择变更应执行对应设备/构建验收。
- PostgreSQL、真实上游接口和 Android 真机结果必须记录实际执行情况。静态解析、单元测试或模拟数据不能替代真实环境验收。
- 修改 Compose、迁移或连接配置时，不提交 `.env`、密码、生产连接信息，也不要删除有价值的数据卷。

## 7. 文档维护规则

命令、端口、目录、数据边界或构建产物发生变化时，先更新本文档，再更新根目录 `AGENTS.md` 的索引。新增功能不再追加长篇会话台账；把稳定的约束写入本文档，把短期测试结果写在提交或评审记录中。
