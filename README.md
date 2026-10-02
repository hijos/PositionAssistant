# PositionAssistant（持仓助手）

PositionAssistant 由 Express 服务、独立额度服务和 Flutter Android/Web 客户端组成。早期 `web/` 原型仍保留作兼容参考。

## 快速开始

```bash
npm ci
npm start
```

主服务默认运行在 <http://localhost:3000>。需要额度服务时另开终端执行 `npm run start:quota`，默认地址为 <http://localhost:4100>。

完整的 PostgreSQL、迁移、测试、Flutter 和 APK 说明见 [`docs/project-guide.md`](docs/project-guide.md)。
