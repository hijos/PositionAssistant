import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:position_assistant/main.dart';

void main() {
  for (final size in [const Size(320, 640), const Size(1280, 800)]) {
    testWidgets('navigation and placeholders at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const PositionAssistantApp());
      // Local storage is Android-only, so this run renders the failure state of
      // the holdings overview. It must still be a full-width card with the five
      // labelled rows rather than a small square or a wall of plain text.
      expect(find.byType(HoldingOverviewCard), findsOneWidget);
      expect(find.text('持仓概览'), findsOneWidget);
      expect(find.text('总市值'), findsOneWidget);
      expect(find.text('总收益'), findsOneWidget);
      expect(find.text('总成本'), findsOneWidget);
      expect(find.text('预估市值'), findsOneWidget);
      expect(find.text('预估收益'), findsOneWidget);
      expect(find.text('正式收益'), findsNothing);
      expect(find.textContaining('正式市值'), findsNothing);
      expect(tester.takeException(), isNull);
      // The home tab must keep the fund-management card: it owns the only
      // delete affordance for an added fund.
      await tester.scrollUntilVisible(
        find.text('已添加基金'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('已添加基金'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final sections = {
        '持仓': ['基金搜索与添加', '持仓详情'],
        '交易': ['交易录入', '交易详情'],
        '定投': ['定投计划编辑'],
        '额度': ['额度详情与手动修改'],
        '设置': ['登录', '注册', '数据导入', '数据导出', '覆盖确认'],
      };
      for (final section in sections.entries) {
        await tester.tap(find.text(section.key).last);
        await tester.pumpAndSettle();
        for (final title in section.value) {
          if (title == '数据导出') {
            // Covered by Android device acceptance; no desktop system picker.
            continue;
          }
          final entry = find.text(title);
          await tester.scrollUntilVisible(
            entry,
            160,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(entry);
          await tester.pumpAndSettle();
          expect(
            find.text(
              title == '基金搜索与添加'
                  ? '基金名称或代码'
                  : title == '登录'
                  ? '邮箱'
                  : title == '交易录入'
                  ? '暂无可用基金'
                  : title == '交易详情'
                  ? '交易记录'
                  : title == '持仓详情'
                  ? '持仓读取失败，请重试'
                  : title == '数据导入'
                  ? '选择 JSON 文件'
                  : title == '定投计划编辑'
                  ? '定投计划'
                  : title == '额度详情与手动修改'
                  ? '额度列表'
                  : '功能准备中',
            ),
            findsOneWidget,
          );
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(find.byType(NavigationBar), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
    });
  }
}
