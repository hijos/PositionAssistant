# PostgreSQL 开发环境（F03）

需要已启动的 Docker Engine（Windows/macOS 可使用 Docker Desktop，选择 Linux 容器）和 Docker Compose v2，支持 `up --wait`。在仓库根目录执行以下命令；Windows 可使用 Git Bash。

## 首次启动

1. `cp .env.example .env`，编辑 `.env`，为 `POSTGRES_PASSWORD` 设置非空本地密码。建议使用随机字母数字密码以避免 Compose 插值转义问题。`.env` 已被 Git 忽略。
2. `docker version` 和 `docker compose version`，确认引擎可连接。
3. `docker compose config --quiet`，验证配置（不要将包含密码的完整 config 输出提交或分享）。
4. `docker compose up -d --wait --wait-timeout 120`。
5. `docker compose ps`，确认 postgres 为 healthy。
6. `docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -c "SELECT current_database(), current_user, version();"'`，验证 SQL 执行。

数据库只绑定 `127.0.0.1:5432`，避免开发数据库暴露到局域网；端口冲突时在 `.env` 修改 `POSTGRES_PORT`。本机客户端使用该端口和 `.env` 中的数据库、用户名、密码；以后同一 Compose 网络中的后端使用 `postgres:5432`。

此服务使用 PostgreSQL 17 和命名卷 `postgres_data`（Compose 项目前缀为 `positionassistant-dev`）。健康检查使用容器内环境变量，每 5 秒执行 `pg_isready`；它检查服务就绪状态，SQL 命令另外验证数据库可查询。当前原型仍使用 JSON 存储，本任务不将原型切换到 PostgreSQL。业务表和迁移机制属于 F04。

## 启停与诊断

- 启动或恢复：`docker compose up -d --wait --wait-timeout 120`。
- 暂停：`docker compose stop`。
- 删除开发容器和网络，保留数据库卷：`docker compose down`。
- 查看状态：`docker compose ps`；查看日志：`docker compose logs --tail 100 postgres`。
- `docker compose down -v` 会删除数据库卷及全部数据，仅在明确需要重置开发数据库时手动使用。

`POSTGRES_*` 初始化参数仅在空数据卷首次启动时生效。修改已有卷的 `.env` 不会自动改数据库、用户或密码。不要通过删卷解决有价值数据的密码问题。保持 PostgreSQL 主版本为 17，主版本升级需单独规划迁移。

## 持久化与恢复验收

在无同名验收表的开发库执行；若建表提示已存在，先检查旧验收数据，不要覆盖。

```bash
docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1' <<'SQL'
CREATE TABLE f03_persistence_probe (id integer PRIMARY KEY, value text NOT NULL);
INSERT INTO f03_persistence_probe VALUES (1, 'f03-volume-ok');
SQL
docker compose down
docker compose up -d --wait --wait-timeout 120
docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1' <<'SQL'
DO $$ BEGIN
  IF (SELECT value FROM f03_persistence_probe WHERE id = 1) IS DISTINCT FROM 'f03-volume-ok' THEN
    RAISE EXCEPTION 'F03 persistence check failed';
  END IF;
END $$;
DROP TABLE f03_persistence_probe;
SQL
docker compose stop
docker compose up -d --wait --wait-timeout 120
docker compose ps
```

验收要求：上述各命令退出码为 0、重建容器后断言通过，最后再次达到 healthy。执行结果写入 `docs/agent-handoff.md`；仅有配置文件不代表运行验收通过。

## 数据库迁移（F04）

使用 Node.js 22.9+（建议 Node.js 22 LTS 或更高版本）及 npm。在项目根目录执行 `npm ci`，按上文启动 PostgreSQL，设置 `.env` 后执行 `npm run db:migrate`。命令自动读取根目录 `.env`，已导出的环境变量优先；不要把密码写进命令行参数或提交到仓库。

默认连接 `127.0.0.1:POSTGRES_PORT`，沿用 `POSTGRES_DB`、`POSTGRES_USER`、`POSTGRES_PASSWORD`；可设置 `POSTGRES_HOST`，或通过环境变量 `DATABASE_URL` 覆盖整套连接参数。迁移失败返回非零退出码，CLI 不输出数据库驱动异常以避免泄露凭据。

首次运行应输出 `Applied: 0001_initialize.sql`，再次运行输出 `Database is up to date`。当前初始迁移只建立 `positionassistant` schema；后续业务任务通过新增迁移建立表，原 Express JSON 原型暂不切换数据库。迁移记录保存在 `public.schema_migrations`，包含版本、文件名、SHA-256 校验和与执行时间。

迁移文件放在 `server/db/migrations/`，命名为 `0002_description.sql`，四位递增编号且不可重复。已执行文件不可修改、删除、重命名或插入旧编号；修正通过新增迁移完成。文件内容必须是可在事务内执行的 PostgreSQL SQL，禁止自行 BEGIN/COMMIT/ROLLBACK、事务外 DDL（例如 CREATE INDEX CONCURRENTLY）及外部副作用。一个批次全部成功后才提交，失败则全部回滚。事务级 advisory lock 将使用本执行器的并发迁移串行化；不得绕过执行器手动改历史表。不提供自动降级或删库重置命令。

### 测试与 Linux 验收

- `npm run test:migrations`：无需数据库的执行流程单元测试；不代表 PostgreSQL 实际执行通过。
- 设置环境变量 `TEST_DATABASE_URL`，指向独立开发 PostgreSQL 实例中有 CREATEDB 权限的账号，然后运行 `npm run test:migrations:integration`。测试会创建随机命名的临时数据库，验证空库初始化、并发执行、重复执行、DDL 与历史记录回滚、校验和保护，并在结束时删除自己创建的数据库。不要指向生产实例。未设置变量时测试明确显示 skipped。
- 在 Linux 开发库连续运行两次 `npm run db:migrate`，确认上述首次/重复输出；可用 `docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -c "TABLE public.schema_migrations;"'` 检查只有一条初始版本记录。

出现失败时先确认连接配置和数据库权限，再对照迁移文件核对历史表版本与校验和。不要通过修改历史记录来强行忽略差异。尚未在真实 PostgreSQL 验收的结果必须保留为待验证。

## 基金目录（F11）

先执行 `npm run db:migrate` 应用 `0003_fund_catalog_cache.sql`。目录使用 PostgreSQL 公共缓存，其他原型业务仍沿用 JSON。启动后端可使用 `node --env-file-if-exists=.env server/index.js`，连接变量与迁移一致。

`GET /api/fund-catalog` 返回 `{items, source, sourceUrl, fetchedAt, stale, refreshError}`。条目包含 code/name/shortName/type；目录尚未进行 F12 的人民币场外过滤，不能直接把全部条目视为允许添加的基金。前端只依赖本服务接口。原有搜索和额度目录调用已共用该服务。

适配器约定为 `{id, sourceUrl, fetchCatalog()}`，通过 `createCatalogService` 注入替换；快照以适配器 id 隔离。当前东方财富适配器仅解析 JSON 数据，不执行远端脚本，使用 10 秒请求超时并拒绝空目录、重复代码和无效记录。数据源协议或解析规则改变时使用新 id。

首次请求采集，快照有效期 24 小时，过期时按需刷新；同一服务进程内并发请求合并，失败后 60 秒再尝试。缓存成功写入后才更新内存；刷新失败保留旧时间戳并返回 stale=true，无缓存返回 503。数据库不可用时冷启动也返回 503，不降级为种子基金。跨进程请求不合并，写入使用单语句原子 upsert。旧 JSON fundCatalog 无可信采集时间，不自动迁移。

运行 `npm run test:catalog` 验证解析、缓存、失败和 HTTP 契约。Linux 中设置独立开发实例的 TEST_DATABASE_URL（CREATEDB 权限）后运行 `npm run test:catalog:integration`，测试创建并清理随机临时库，验证完整迁移、跨连接持久化与失败保留。随后启动服务访问 `/api/fund-catalog`，检查真实上游来源、条目和时间戳，重启后确认 fetchedAt 不变。当前未执行真实上游联通验收。

## F12 基金搜索

`GET /api/funds/search?q=基金名称或代码` 返回最多20条目录记录，按代码排序、完整代码优先；空查询返回空数组，非字符串或超过100字符返回400，目录不可用返回503。名称、代码和拼音简称支持包含匹配，输入做 NFKC、去首尾空格和大小写规范化。搜索复用公共目录缓存，不写入用户数据。

人民币场外筛选使用目录名称和类型：排除 ETF（保留名称中明确 ETF 联接/连接）、LOF、场内/交易型/封闭/REIT 及常见外币标记，仅接纳股票/混合/债券/货币/指数/QDII/FOF 已知类型。原始目录接口保留完整快照。上游目录没有独立币种、交易场所字段，因此这是保守文本规则，不能替代基金公司资料核验；未知类型会被排除。部署验收应抽查实际目录的普通人民币基金、外币份额、ETF、LOF、ETF联接，并记录误判后完善适配层。

Flutter 搜索页通过后端访问目录；Web 默认同源，开发时需代理 `/api/` 到 Node 服务；Android 默认地址 `http://10.0.2.2:3000` 仅用于模拟器开发。正式 Android 请使用 `--dart-define=API_BASE_URL=https://你的服务域名`，Web 跨域部署需在反向代理配置允许的来源。Android 已声明 INTERNET 权限，未全局放开明文 HTTP。即使本地模式，搜索公共目录仍需要联网；添加到当前数据源由 F13 实现。

本机验证：`node --test test/fund-search.test.js test/catalog.test.js`；在 client 下运行 `flutter test` 和 `flutter analyze`。真实 Linux 服务及终端联调尚待验收。

## F14 正式净值

正式净值由 `server/nav/` 的可替换适配器采集，默认使用东方财富历史净值接口；服务只解析 JSON 响应，不执行上游脚本。`GET /api/funds/:code/nav` 返回最新正式净值，`GET /api/funds/:code/nav/history` 返回历史记录。记录包含净值日期、来源标识、来源 URL 和采集时间；`?refresh=1` 强制刷新，刷新失败时保留并标记历史缓存。

Android 本地模式不依赖持仓助手服务端：`client/lib/data/nav_repository.dart` 直接请求东方财富 `f10/lsjz` 历史接口，并将结果写入 SQLite 的 `navSnapshots` 集合。东方财富接口可能忽略日期范围且固定每页 20 条，因此客户端必须分页读取至覆盖目标日期，再按交易日期和截止时间选择首个不早于起点的正式净值。已缓存的净值可离线使用，未缓存且无法联网时交易保持待确认。

迁移 `0005_nav_snapshots.sql` 建立按基金、净值日期和来源去重的 PostgreSQL 历史快照表。首次请求或缓存超过 24 小时才采集，同一进程并发请求合并；数据库不可用或无历史缓存时接口返回 502。估算值仍属于后续估算链路，不写入正式净值表。

本机验证：`npm run test:nav`、`node --check server/nav/index.js`、`node --check server/index.js`。真实 PostgreSQL 迁移、跨重启历史持久化和东方财富联通需在 Linux 环境执行。

## F16 净值日期判定

交易日期先按北京时间 15:00 分界：15:00 前从交易当日开始匹配，15:00 后从下一自然日开始匹配。服务请求正式净值历史后，选择不早于该起点的首个 `navDate`；周末和节假日因没有正式净值记录会自然跳过，使用上游历史作为交易日历，不维护本地节假日表。历史尚未公布到目标日期时保留待确认状态，后续确认任务可再次执行同样判定。

本机验证：`node --test test/trading-date.test.js test/accounting.test.js`、`node --check server/trading-date.js`、`node --check server/index.js`。测试覆盖 15:00 前后、周五跨周末、周末/节假日缺少记录、无后续净值和日期输入校验。

## F26 指数行情与汇率

指数行情与汇率由 `server/market/` 的可替换适配器采集，默认使用 Yahoo Finance 日线接口；服务只解析 JSON 响应，不执行上游脚本。`GET /api/market/:symbol/quote` 返回最新一条行情，`GET /api/market/:symbol/history` 返回日线历史；symbol 需 URL 编码（如 `%5ENDX`、`CNY%3DX`）。公开接口当前只接受 `^NDX`（纳斯达克100）、`^GSPC`（标普500）和 `CNY=X`（USD/CNY），其他合法代码返回 400；适配器内部仍保留通用代码校验，供后续估算链路注入使用。记录包含交易日期、收盘价、来源标识、来源 URL 和采集时间；`?refresh=1` 强制刷新，刷新失败时保留并标记历史缓存。

迁移 `0006_market_snapshots.sql` 建立按行情代码、交易日期和来源去重的 PostgreSQL 快照表；读缓存、写缓存和 TTL 判断均按适配器 `id` 隔离。缓存有效期 15 分钟，过期才重新采集，同一进程并发请求合并；数据库不可用或无历史缓存时接口返回 502。行情日期使用交易所时区换算；适配器约定为 `{id, fetchHistory(symbol)}`，通过 `createMarketService` 注入替换，协议变化时使用新 id。行情数据只服务于 F27 起的估算链路，不写入正式净值或收益账本。

本机验证：`npm run test:market`、`node --check server/market/index.js`、`node --check server/index.js`。真实 PostgreSQL 迁移、跨重启快照持久化和 Yahoo Finance 联通需在 Linux 环境执行。

## F35 自动额度采集

`POST /api/quotas/refresh` 从基金目录筛选纳斯达克100和标普500 QDII 人民币份额，读取东方财富基金详情页的申购状态与单日累计购买上限；无法从页面解析具体金额时可使用已核验的基金管理人公告补充值。自动记录包含分类、来源、来源类型、来源 URL 和更新时间。刷新时保留已有用户覆盖，并把新自动值写入 `automaticStatus`/`automaticLimit`，供后续恢复功能使用。

本机验证：`node --check server/quotas.js`、`node --check server/index.js`、`node --test test/quotas.test.js`。真实目录、基金详情页和 PostgreSQL 部署联通仍需在 Linux/上游环境验收。

## F39 多渠道额度与直销入口配置

额度记录支持 `channels.distribution` 和 `channels.direct` 两个渠道，旧版 `status`/`limit` 字段继续映射到推荐渠道，旧缓存读取时自动解释为代销渠道。直销来源只使用公开、无需登录和验证码的基金公司页面；当前已配置华夏基金产品销售网点页、易方达网上交易购买页、南方基金个人理财详情页、摩根基金产品页、广发基金产品页、国泰基金产品页、招商基金产品页、博时基金产品页、汇添富基金产品页、嘉实基金产品页、华宝基金产品详情页和建信基金产品详情页的代码级入口模板，按基金代码生成 URL。入口存在不等于额度已确认：页面解析失败、需要登录或没有公开限额时，直销渠道保持“未知/未披露”，不会写入 0。

天弘官方基金详情页入口已确认：`https://www.thfund.com.cn/fundinfo/{code}`。浏览器可见页面会显示申购状态；当前已验证 018043 显示“申购状态：关闭”，按业务规则对应直销额度 0。由于服务端请求仍可能命中阿里云 WAF，天弘自动采集保持关闭，避免将挑战页误当基金数据。；目录中“摩根”基金已确认使用摩根基金（cifm.com），不是摩根士丹利基金，待确认其公开直销产品页或公告入口后再加入配置。直销适配器返回 `fund-manager-page` 来源类型；自动刷新会分别统计代销更新、直销更新、直销不可用和失败数量。手动覆盖支持 `channel=direct|distribution`，并保存为 `channels.<channel>.<field>` 覆盖字段。 南方基金另有公开 `subscriptionAndRedemptionStatus` 接口，适配器会按基金代码读取状态与官方备注；基金公司官方页面、官方公告和官方接口默认按直销口径解释；同时保留 `officialRestriction` 和来源信息，便于后续发现渠道例外时修正。

本机验证：`node --check server/index.js`、`node --check server/quota-sources/direct-config.js`、`node --check server/quota-sources/fund-manager.js`、`node --test test/quota-direct-config.test.js test/quotas.test.js test/quotas-http.test.js`。

## 独立额度子服务（手工数据第一版）

额度子服务位于 `quota-service/`，启动入口为 `quota-service/index.js`，不依赖 `server/index.js`、持仓账号或持仓数据库。第一版不执行上游爬取，管理员通过独立管理页面手动维护基金名称、纳斯达克100/标普500分类、直销/代销状态、单日额度和渠道费率。公共 App 接口为 `GET /api/quotas`，纠错提交接口为 `POST /api/corrections`。

Windows 局域网开发时设置 `QUOTA_ADMIN_PASSWORD`（至少 8 个字符），再运行 `npm run start:quota`。服务默认监听 `0.0.0.0:4100`，手机与电脑连接同一 WiFi 后使用 `http://电脑局域网IP:4100`；Windows 防火墙需要允许专用网络的 TCP 4100 入站访问。管理页面位于根路径，健康检查为 `/health`。额度数据默认写入被 Git 忽略的 `quota-service/data/db.json`。

Flutter 使用独立的 `QUOTA_SERVICE_URL`。运行 `scripts\build-apk.bat` 时，脚本会自动把云端地址 `https://quota.yexl.top` 编译进 debug/release APK；App 的额度读取、云端版本刷新和“保存并上传”都走该地址。App 的“保存”只保存个人覆盖，“保存并上传”在个人保存成功后额外提交纠错建议，上传失败不会撤回个人保存。若要在局域网开发额度子服务，可手动通过 `--dart-define=QUOTA_SERVICE_URL=http://电脑局域网IP:4100` 覆盖。

纠错按服务端看到的来源 IP 做哈希去重，同一基金、渠道和云端版本内每个 IP 只保留一票。自动采纳同时要求达到最低支持数和一致性比例，默认是 3 个来源、80%、72 小时窗口；管理员可在管理页面调整。管理员可在“用户纠错建议”表格中二次确认后接受或删除待处理建议；接受会直接覆盖当前渠道值并写入“管理员主动接受建议”审计记录。满足门槛的自动采纳在审计表中显示为“系统自动接受建议”，仍可在没有后续更新时撤销。每次手工修改、建议接受、共识覆盖和管理员撤销均写入审计记录。

本机验证：`npm run test:quota-service`、`node --check quota-service/index.js`、`node --test test/quotas.test.js test/quotas-http.test.js`；客户端验证：在 `client/` 执行 `flutter analyze`、`flutter test test/quota_repository_test.dart`。管理密码和 IP 哈希盐不得提交到仓库。
## F37 用户额度覆盖、优先级和隔离

额度自动记录与用户覆盖记录按同一基金代码分开保存。`PUT /api/quotas/:code` 只写入当前
Bearer 账号的覆盖记录，可单独修改 `status` 或 `limit`；覆盖记录保留 `automaticStatus`、
`automaticLimit` 和 `overrideFields` 作为自动基线。`GET /api/quotas` 和额度刷新响应只返回当前
账号可见的有效值：有覆盖时 `valueSource`/`priority` 为 `user`，否则为 `automatic`。自动刷新会更新
所有覆盖记录的自动基线，不会覆盖用户值；不同账号可以对同一代码分别覆盖，且互不可见、互不可改。

本机验证：`node --check server/quotas.js`、`node --check server/index.js`、内联 Web 脚本
`node --check`，`node --test test/quotas.test.js test/quotas-http.test.js`。真实远端部署与多进程
持久化仍需在 Linux 环境验收。

## F38 恢复自动额度数据

`POST /api/quotas/:code/restore` 需要当前账号登录。服务端先重新采集该基金的自动额度，成功后删除当前账号的覆盖记录，将最新自动记录保存为公共基线，并同步其他账号覆盖记录中的 `automaticStatus`/`automaticLimit`；其他账号仍保留自己的覆盖字段。当前账号随后返回 `valueSource=automatic`。没有当前账号覆盖但存在公共自动记录时，接口仍会刷新自动记录；两者都不存在返回 404。采集失败返回 502，已有覆盖和自动数据保持不变。

本机验证：`node --check server/quotas.js`、`node --check server/index.js`、`node --test test/quotas.test.js test/quotas-http.test.js`。

## F40 导入文件预检和数据概要

`POST /api/import/preview` 需要 Bearer 登录，并接收 F39 的版本化 JSON 导出包。服务端只校验包格式、版本、导出时间、五类
数据数组及其记录类型，然后返回 `valid` 和 `summary`；概要包含各类记录数量、总数、涉及的基金代码，以及交易和定投记录状态
统计。预检阶段不会写入 JSON 数据库，也不会执行覆盖导入；后续 Android 本地和远端覆盖导入及事务回滚分别属于 F41/F42。

Web 设置页可以选择 `.json` 文件并显示预检结果，确认覆盖导入仍留待后续任务。格式错误、版本不支持或数据结构无效返回 400，
未登录返回 401。

本机验证：`node --check server/import.js`、`node --check server/index.js`、`node --test test/import.test.js test/export.test.js`。
真实 Android 文件选择、SQLite/PostgreSQL 覆盖导入和失败回滚尚未执行，留待 F41/F42 及 Linux/真机环境验收。

## F41 Android 本地事务覆盖导入和回滚

Android 本地设置页使用系统 `ACTION_OPEN_DOCUMENT` 选择 JSON 文件；客户端先校验 `position-assistant.export` v1
的导出时间、五类数组和各集合主键，并展示记录概要。用户确认后，`importLocalPackage` 在一个 SQLite transaction
中完整替换 `funds`、`transactions`、`plans`、`planEntries` 和 `quotaOverrides`；任何校验或写入异常都会回滚，原数据保持不变。
远端导入仍属于 F42。

本机验证：在 `client/` 执行 `flutter analyze`、`flutter test` 和 `flutter test test/import_repository_test.dart` 均通过。
专项测试覆盖完整替换、重复主键拒绝、跨五集合中途失败回滚和关闭重开后的持久化。当前 Windows 环境的 Android Gradle
构建在 `sqflite_android` 生成 `R.jar` 时持续返回 `AccessDeniedException`，需在可用 Android/Gradle 环境重跑
`flutter build apk --debug` 和真机文件选择验收。

## F27 基金估算规则

估算规则位于 `server/estimation.js`，当前版本为 `us-equity-weighted-fx-v1`。输入必须携带基金代码、正式净值及净值日期、带披露日期的美股持仓权重和行情/汇率快照；规则按披露权重计算美股涨跌并叠加 USD/CNY 变化，未覆盖资产按零收益处理。输出包含规则版本、估算基准日、持仓覆盖率和披露日期。更换规则时使用新版本号，估算值不写入正式净值或收益账本。
## F13 添加基金

- 运行 `npm run db:migrate` 应用 `0004_user_funds.sql`，启动服务时提供 `DATABASE_URL`。
- Flutter 搜索结果点击“添加”写入打开页面时的当前数据源；本地使用 SQLite `funds` 集合，远端使用带 Bearer 凭据的 `GET/POST /api/my-funds`。POST 只发送六位 `code`，服务端从 F11 目录核验 F12 支持规则并保存 `code/name/type`。代码区分 A/C 等份额，名称原样保留；未猜测缺失份额字段。
- 远端以 `(owner_id, code)` 唯一键防止重复和并发添加，保存首次添加信息；本地通过事务达到同样效果。添加不创建交易或虚构持仓/净值。
- 设置中可切换数据源和登录已有账号；凭据仅保存在内存，刷新页面或重启 App 后需重新登录。退出会先清除本机凭据，再请求服务端注销。搜索页返回后刷新已添加列表；首次启动可点击“读取已添加基金”。
- **历史实现缺口核实**：当前 `server/index.js` 注册/登录实际仍用 `data/db.json` 用户和进程内 sessions，尚未使用 `0002_users.sql`。因此 F13 的 PostgreSQL `owner_id` 暂用既有账号字符串，不伪造 users 外键；部署必须保留原 JSON 用户文件。未来迁移认证必须保留或显式映射 owner_id。服务重启会失效会话，账号保存的基金仍在 PostgreSQL。此处不代表 F06–F10 验收通过。
- 本机测试：`node --test test/funds.test.js`；Flutter `flutter test`。Linux 专项数据库测试复用 `TEST_DATABASE_URL=... node --test test/catalog.integration.test.js` 的随机临时数据库流程，新增跨连接并发添加及账号隔离断言；需要独立测试实例和 CREATEDB 权限。
- Linux 联调：使用两个账号分别登录；一个账号添加相同代码多次，列表只有一项，另一个账号列表为空；重启服务后重新登录仍可读取。Android 本地添加后关闭重开、切远端再切回，本地记录应保留且不出现在远端。真实目录筛选及设备网络仍需验收。


