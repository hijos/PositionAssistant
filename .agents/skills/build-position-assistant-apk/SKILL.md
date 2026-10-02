---
name: build-position-assistant-apk
description: 为 PositionAssistant（持仓助手）项目打包 Android APK。当用户在本项目中要求“打包 / 构建 / 出个 apk / 重新打包最新安装包 / 出 release 包”时使用；默认只构建 arm64-v8a（arm-v8）架构；用户说“打包一个带额度数据的apk”时，先同步额度子服务最新数据并生成内置额度初始数据，产物命名为 持仓助手-带额度.apk。
---

# 打包持仓助手 APK（PositionAssistant）

项目结构：Flutter 客户端位于 `client/`，仓库根目录自带工具链：
- Flutter SDK：`.tooling/flutter`（stable 3.47.4，勿用系统 PATH 里的 flutter，可能不存在或版本不符）
- Android SDK：`C:\lib`（`client/android/local.properties` 已配置 `sdk.dir=C:\\lib`）

## 打包步骤

1. 确认当前目录为仓库根（`C:\Users\ms-ml\.ccgui\workspace\PositionAssistant`）。不要 `flutter clean`——会浪费数分钟重建 Gradle 缓存；增量构建即可，Flutter 会自动包含最新代码。

2. **必须使用仓库根目录的 `scripts\build-apk.bat` 打包**，不要直接在 `client/` 下调用 `flutter build apk`。该脚本会注入云端额度服务地址 `QUOTA_SERVICE_URL=https://quota.yexl.top`；否则 APK 可能回退到手机上的 `127.0.0.1:4100`，导致无法访问额度服务。

   在项目根目录执行：

   ```powershell
   .\scripts\build-apk.bat
   ```

   用户明确要求 debug 包时执行：

   ```powershell
   .\scripts\build-apk.bat debug
   ```

   用户明确说“打包一个带额度数据的apk”时执行：

   ```powershell
   .\scripts\build-apk.bat with-quota
   ```

   所有模式都只构建 Android `arm64-v8a`（arm-v8）架构，不生成 `armeabi-v7a`、`x86_64` 或多架构组合包。`with-quota` 模式会在构建前读取 `quota-service/data/db.json`，将其中最新的 `quotas` 数组同步到 `data/db.json`，生成临时 Flutter 资源并以 `BUNDLE_QUOTA_DATA=true` 编译。APK 首次安装时会把这批额度写入本地 SQLite，作为额度页面的初始数据；已有安装的数据和用户覆盖不会被启动时覆盖。构建完成后临时资源会清空，普通 APK 仍不预置额度数据。

   首次或依赖变更时若脚本构建异常，先在 `client/` 下运行 `..\.tooling\flutter\bin\flutter.bat pub get`，再从项目根目录重新执行脚本。

3. 构建会产生两份相同内容的 arm64-v8a APK（Flutter 工具行为：`build/app/outputs/flutter-apk/` 是从 Gradle 输出 `build/app/outputs/apk/release/` 复制来的）。**只保留一份**：先删除旧的目标 APK，再把 Gradle 输出移动重命名过去。普通 release/debug 包的目标名是 `持仓助手.apk`；`with-quota` 模式的目标名是 `持仓助手-带额度.apk`。

   **两种命名产物必须共存**：构建 `持仓助手.apk` 时不得删除输出目录里已有的 `持仓助手-带额度.apk`；构建 `持仓助手-带额度.apk` 时同样不得删除已有的 `持仓助手.apk`。只清理与本次构建同名的旧目标和 Flutter 复制出的 `app-release.apk` / `app-debug.apk`。

   `scripts\build-apk.bat` 会调用 `scripts\rename-apk.ps1` 完成删除旧目标和移动重命名，不要手动复制 APK。

   最终产物：

   - 普通包：`client\build\app\outputs\flutter-apk\持仓助手.apk`
   - 带额度包：`client\build\app\outputs\flutter-apk\持仓助手-带额度.apk`

   `app-release.apk` 或 `app-debug.apk` 不保留为重复交付文件。

4. 验证 LastWriteTime 为当前时间、大小约 50MB，把对应的绝对路径告知用户：

   - 普通包：`C:\Users\ms-ml\.ccgui\workspace\PositionAssistant\client\build\app\outputs\flutter-apk\持仓助手.apk`
   - 带额度包：`C:\Users\ms-ml\.ccgui\workspace\PositionAssistant\client\build\app\outputs\flutter-apk\持仓助手-带额度.apk`

## 注意

- 不要用 `Copy-Item` 再保留原名文件——用户明确要求不保留重复 APK 副本；用移动/重命名替代复制。
- 两种产物在输出目录共存：`rename-apk.ps1` 只删除本次同名的旧目标及 `app-release.apk` / `app-debug.apk`，不会动另一种命名产物；不要改回全量清理，也不要手动删除另一种 APK。
- 默认打 release 包；只有用户明确要求 debug 时才用 `--debug`。
- 当前未配置正式签名，release APK 使用默认 debug 签名，可直接安装但不能上架。用户提到上架/正式分发时再引导配置 keystore。
- 构建耗时约 1–3 分钟属正常；Gradle 报 daemon/JDK 相关错误时检查 Java 17 是否可用（`java -version`）。
