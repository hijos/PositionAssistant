import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:position_assistant/main.dart';
import 'package:position_assistant/offline_pages.dart';
import 'package:position_assistant/transaction_history.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  for (final size in [const Size(320, 640), const Size(1280, 800)]) {
    testWidgets('navigation and reorganized pages at $size', (tester) async {
      Future<void> settleRoute() async {
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
      }

      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const PositionAssistantApp());

      expect(find.byType(HoldingOverviewCard), findsOneWidget);
      expect(find.text('持仓概览'), findsOneWidget);
      expect(find.text('总市值'), findsOneWidget);
      expect(find.text('总收益'), findsOneWidget);
      expect(find.text('总成本'), findsOneWidget);
      expect(find.text('预估市值'), findsOneWidget);
      expect(find.text('预估收益'), findsOneWidget);
      expect(find.text('正式收益'), findsNothing);
      expect(find.textContaining('正式市值'), findsNothing);
      expect(find.text('添加持仓'), findsOneWidget);
      expect(find.text('基金搜索与添加'), findsNothing);
      expect(find.text('持仓详情'), findsNothing);

      await tester.scrollUntilVisible(
        find.text('添加持仓'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('添加持仓'));
      await settleRoute();
      expect(find.text('交易录入'), findsOneWidget);
      await tester.pageBack();
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('交易').last);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(TransactionHistoryPage), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('交易记录'), findsOneWidget);
      expect(find.text('交易录入'), findsNothing);
      expect(find.text('交易详情'), findsNothing);
      // The cleanup action sits in the app bar, next to the 交易记录 title.
      expect(find.byTooltip('清理已取消交易'), findsOneWidget);

      await tester.tap(find.text('自选').last);
      await settleRoute();
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byTooltip('清理已取消交易'), findsNothing);
      expect(find.textContaining('已添加基金'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byType(FloatingActionButton));
      await settleRoute();
      expect(find.text('基金名称或代码'), findsOneWidget);
      await tester.pageBack();
      await settleRoute();

      await tester.tap(find.text('持仓').last);
      await settleRoute();
      // The holdings tab carries its own overview card, so the shell hides
      // the app bar there; the same holds for the settings tab below.
      expect(find.byType(AppBar), findsNothing);
      await tester.scrollUntilVisible(
        find.text('定投计划'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('定投计划'));
      await settleRoute();
      expect(find.byType(LocalPlansPage), findsOneWidget);
      expect(find.text('页面预览'), findsNothing);
      await tester.pageBack();
      await settleRoute();

      await tester.tap(find.text('额度').last);
      await settleRoute();
      // The quota tab now renders its own content without a shell app bar,
      // mirroring the holdings/watchlist/settings tabs.
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('额度'), findsWidgets);
      expect(find.text('保存并上传'), findsNothing);

      await tester.tap(find.text('设置').last);
      await settleRoute();
      expect(find.byType(AppBar), findsNothing);
      // Local mode hides the account section entirely; switching to remote
      // mode via the segmented control reveals the login entry.
      expect(find.text('本地模式'), findsOneWidget);
      expect(find.text('远端账号'), findsNothing);
      expect(find.text('登录'), findsNothing);
      await tester.tap(find.text('远端模式'));
      await settleRoute();
      expect(find.text('远端账号'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('登录'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('登录'));
      await settleRoute();
      expect(find.text('邮箱'), findsOneWidget);
      await tester.pageBack();
      await settleRoute();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
