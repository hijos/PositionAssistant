import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:position_assistant/main.dart';
import 'package:position_assistant/transaction_history.dart';

void main() {
  for (final size in [const Size(320, 640), const Size(1280, 800)]) {
    testWidgets('navigation and reorganized pages at $size', (tester) async {
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
      await tester.pumpAndSettle();
      expect(find.text('暂无可用基金'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('交易').last);
      await tester.pumpAndSettle();
      expect(find.byType(TransactionHistoryPage), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('交易记录'), findsOneWidget);
      expect(find.text('交易录入'), findsNothing);
      expect(find.text('交易详情'), findsNothing);
      // The cleanup action sits in the app bar, next to the 交易记录 title.
      expect(find.byTooltip('清理已取消交易'), findsOneWidget);

      await tester.tap(find.text('自选').last);
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byTooltip('清理已取消交易'), findsNothing);
      expect(find.textContaining('已添加基金'), findsNothing);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.text('基金名称或代码'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('持仓').last);
      await tester.pumpAndSettle();
      // The holdings tab carries its own overview card, so the shell hides
      // the app bar there; the same holds for the settings tab below.
      expect(find.byType(AppBar), findsNothing);
      await tester.scrollUntilVisible(
        find.text('定投计划'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('定投计划'));
      await tester.pumpAndSettle();
      expect(find.text('定投计划'), findsOneWidget);
      expect(find.text('页面预览'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('额度').last);
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('额度详情与手动修改'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('额度详情与手动修改'));
      await tester.pumpAndSettle();
      expect(find.text('额度列表'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('设置').last);
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      await tester.scrollUntilVisible(
        find.text('登录'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('登录'));
      await tester.pumpAndSettle();
      expect(find.text('邮箱'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
