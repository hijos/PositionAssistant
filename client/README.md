# 持仓助手 Flutter 客户端

客户端位于 `client/`，共用 Android/Web 代码，支持本地 SQLite 模式和访问 Express 的远端模式。持仓、交易、定投、额度、导入导出等业务入口已经接入；不要再把本目录描述为“只有页面占位”。早期 Express/Web 原型位于上级 `server/` 与 `web/`，不作为 Flutter 本地模式的存储依赖。

仓库自带 Flutter SDK，常用命令如下：

```powershell
..\.tooling\flutter\bin\flutter.bat pub get
..\.tooling\flutter\bin\flutter.bat analyze
..\.tooling\flutter\bin\flutter.bat test
..\.tooling\flutter\bin\flutter.bat run -d chrome
..\.tooling\flutter\bin\flutter.bat build web
```

Android SDK 使用 `C:\lib`，配置见 `android/local.properties`。Android 模拟器访问本机主服务时通常使用 `http://10.0.2.2:3000`；正式环境通过 `API_BASE_URL` 注入 HTTPS 地址。额度服务地址通过 `QUOTA_SERVICE_URL` 注入。

Android APK 必须从仓库根目录执行 `scripts\build-apk.bat`，包括 `debug` 和 `with-quota` 模式。不要使用 `flutter clean`；产物和验证步骤见 [`../docs/project-guide.md`](../docs/project-guide.md)。

## 本地数据边界

Android 本地仓储使用应用私有 SQLite 数据库 `position_assistant.db`。业务 Repository 通过接口和事务会话访问存储，不应在事务回调内发起网络副作用。金额和份额使用十进制字符串，业务模型必须在 payload 中保留自己的 id。

本地正式净值由 `lib/data/nav_repository.dart` 直接请求东方财富历史净值接口，并写入 `navSnapshots`；请求失败时保留缓存，交易不得被错误地标记为已确认。Web 不使用 SQLite 工厂，远端数据必须通过服务端接口获取。

相关测试：

```powershell
..\.tooling\flutter\bin\flutter.bat test test/repository_test.dart
..\.tooling\flutter\bin\flutter.bat analyze
```
