# PositionAssistant 项目指引

本文件只记录本仓库的结构、不可违反的开发约定和常用入口。完整的环境、命令、架构边界与验收说明见 [`docs/project-guide.md`](docs/project-guide.md)。

## 项目结构

- `server/`：Node.js/Express 服务。`server/index.js` 默认监听 `http://localhost:3000`，账号、交易和部分原型数据仍使用 `data/db.json`。
- `server/db/`：PostgreSQL 迁移执行器和迁移文件。基金目录、正式净值和市场行情缓存使用 PostgreSQL。
- `client/`：Flutter Android/Web 客户端。本地模式使用应用私有 SQLite，远端模式访问 Express 服务。
- `quota-service/`：独立额度数据服务，默认监听 `http://localhost:4100`，使用自己的 `quota-service/data/db.json`。
- `web/`：早期 Web 原型，不能代替 Flutter 客户端的本地/远端实现。
- `scripts/`：数据库迁移、额度同步和 Android 打包脚本。
- `test/`：Node.js 测试；`client/test/`：Flutter 测试。

## 常用入口

在仓库根目录执行：

```bash
npm ci
npm start
npm run start:quota
npm run db:migrate
```

PostgreSQL、Docker Compose、集成测试、Flutter 和 APK 的完整步骤在 [`docs/project-guide.md`](docs/project-guide.md)。

Node.js 修改至少运行对应的 `node --check` 和专项测试；Flutter 修改运行 `.tooling/flutter/bin/flutter.bat analyze` 与相关测试。Android 打包必须使用 `scripts\build-apk.bat`，不要使用 `flutter clean`。

## 不可违反的约定

- `.env`、密码、生产连接信息和真实用户数据不得提交。
- 迁移只能新增四位递增编号的 SQL 文件；已经执行的迁移不可修改、删除、重命名或插入旧编号。
- 上游目录、净值、行情和汇率通过可替换适配器接入；协议或解析规则变化时使用新的适配器标识，并保留来源信息。
- 本地正式净值由 `client/lib/data/nav_repository.dart` 直接请求东方财富历史净值接口并写入 SQLite `navSnapshots`；按交易日期和截止时间选择首个不早于起点的净值。请求失败时交易必须保持待确认。
- 用户数据必须按账号隔离；新增接口要覆盖未登录、越权、重复请求和数据源失败等边界。
- 本地模式与远端模式数据互相独立，切换不自动合并或删除数据；导入覆盖必须在事务中完成，失败时保持原数据。
- 不覆盖用户已有的未提交修改；发现无法解释的外部改动时先暂停处理。

## 项目级 skill

需要新增 skill 时，默认下载到 `%USERPROFILE%/.agents/skills`，并在 `%USERPROFILE%/.claude/skills` 与 `%USERPROFILE%/.codex/skills` 中创建目录软链接。PositionAssistant 的 APK 打包 skill 位于 `.agents/skills/build-position-assistant-apk/`。

## 文档维护

- `docs/project-guide.md` 是当前运行和维护事实的唯一汇总入口。
- `functions.md` 保留为历史产品方案，不能当作当前实现状态；实现以代码、测试和 `docs/project-guide.md` 为准。
- 变更命令、端口、目录或数据边界时，同步更新 `docs/project-guide.md` 和本文件。
