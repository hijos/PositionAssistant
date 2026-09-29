# 持仓助手 Flutter 前端

F02 仅包含 Android/Web 共用入口、卡片布局、底部导航和页面占位。
业务操作尚未接入；收益显示为无数据，不使用虚构金额。

在本目录执行（需要 stable Flutter SDK、Android SDK 和 JDK）：

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d chrome
flutter run -d <android-device-id>
flutter build web
flutter build apk --debug
```

当前工作区的隔离 Flutter SDK 位于 `../.tooling/flutter`，不提交版本库。
Android 默认本地、Web 使用远端的说明仅为界面占位；F05 已提供本地存储工厂，页面业务接入和模式切换由后续任务实现。
原 Express 原型仍在上级 `web/` 和 `server/`，不作为本工程运行依赖。

## F05 本地存储

`lib/data/repository.dart` 定义平台无关 JSON 记录 CRUD 和事务接口；业务层依赖接口，通过构造参数注入，不直接操作 sqflite。远端适配器在后续接口任务实现，不能使用本地数据库冒充远端。

Android 在 `WidgetsFlutterBinding.ensureInitialized()` 后按需调用 `openLocalRepository()`；数据库位于应用私有数据库目录 `position_assistant.db`。调用方持有并在不再使用时关闭 Repository。Web 调用该工厂会明确报错；当前占位 UI 尚无业务读取，因此不在 main 中创建无使用者的连接。

SQLite v1 以 `(collection, id)` 主键隔离记录，payload 保存 JSON 对象。`list` 按 id 排序、返回 payload；业务模型须在 payload 中保留自己的 id。金额和份额应使用十进制字符串，避免二进制浮点损失。此处只是基础存储边界，并非 F39 导出格式或最终业务 schema；具体类型、校验和表结构随后续任务建立。

事务回调只使用传入的 `RepositorySession`，异常自动回滚；不要在回调内调用外部 Repository 或执行网络副作用。未来 schema 变更增加数据库版本和升级逻辑；不允许旧版本应用降级删除数据。

`flutter test test/repository_test.dart` 使用 sqflite FFI 和真实 SQLite 临时文件，覆盖关闭重开持久化、集合隔离、CRUD、事务提交/回滚及无效输入。Android 插件真机运行仍需设备验收。
