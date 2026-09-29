---
name: build-position-assistant-apk
description: 为 PositionAssistant（持仓助手）项目打包最新 Android APK。当用户在本项目中要求"打包 / 构建 / 出个 apk / 重新打包最新安装包 / 出 release 包"等任何关于生成 APK 的请求时使用。产物固定命名为 持仓助手.apk。
---

# 打包持仓助手 APK（PositionAssistant）

项目结构：Flutter 客户端位于 `client/`，仓库根目录自带工具链：
- Flutter SDK：`.tooling/flutter`（stable 3.47.4，勿用系统 PATH 里的 flutter，可能不存在或版本不符）
- Android SDK：`C:\lib`（`client/android/local.properties` 已配置 `sdk.dir=C:\\lib`）

## 打包步骤

1. 确认当前目录为仓库根（`C:\Users\ms-ml\.ccgui\workspace\PositionAssistant`）。不要 `flutter clean`——会浪费数分钟重建 Gradle 缓存；增量构建即可，Flutter 会自动包含最新代码。

2. 执行 release 构建（在 `client/` 下）：

   ```powershell
   cd client
   & ..\.tooling\flutter\bin\flutter.bat build apk --release
   ```

   首次或依赖变更时若构建异常，先跑 `..\.tooling\flutter\bin\flutter.bat pub get` 再重试。

3. 构建会产生两份相同内容的 APK（Flutter 工具行为：`build/app/outputs/flutter-apk/` 是从 Gradle 输出 `build/app/outputs/apk/release/` 复制来的）。**只保留一份**：先删除旧的 `持仓助手.apk`，再把 Gradle 输出移动重命名过去：

   ```cmd
   cmd /c "del /f build\app\outputs\flutter-apk\持仓助手.apk 2>nul & move /y build\app\outputs\apk\release\app-release.apk build\app\outputs\flutter-apk\持仓助手.apk"
   ```

   最终唯一产物：`client\build\app\outputs\flutter-apk\持仓助手.apk`（与 `app-release.apk` 并存，内容相同，删除其一不影响安装）。

4. 验证 LastWriteTime 为当前时间、大小约 50MB，把绝对路径告知用户：

   `C:\Users\ms-ml\.ccgui\workspace\PositionAssistant\client\build\app\outputs\flutter-apk\持仓助手.apk`

## 注意

- 不要用 `Copy-Item` 再保留原名文件——用户明确要求不保留重复 APK 副本；用移动/重命名替代复制。
- 默认打 release 包；只有用户明确要求 debug 时才用 `--debug`。
- 当前未配置正式签名，release APK 使用默认 debug 签名，可直接安装但不能上架。用户提到上架/正式分发时再引导配置 keystore。
- 构建耗时约 1–3 分钟属正常；Gradle 报 daemon/JDK 相关错误时检查 Java 17 是否可用（`java -version`）。
