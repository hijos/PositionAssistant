import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:position_assistant/main.dart';

void main() {
  final fund = {
    'code': '018043',
    'name': '天弘纳斯达克100指数发起(QDII)A',
    'type': '指数型-海外股票',
  };

  Future<void> pumpRow(
    WidgetTester tester,
    List<Map<String, dynamic>> removed,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FundListTile(
            fund: fund,
            onRemove: (item) async => removed.add(item),
          ),
        ),
      ),
    );
  }

  testWidgets('the row exposes no delete button', (tester) async {
    await pumpRow(tester, []);
    expect(find.text('天弘纳斯达克100指数发起(QDII)A'), findsOneWidget);
    expect(find.text('018043'), findsOneWidget);
    expect(find.text('指数型-海外股票'), findsNothing);
    expect(find.text('—'), findsOneWidget);
    // behind background layer
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('the row shows the latest daily change when available',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FundListTile(
            fund: {...fund, 'dailyChange': 1.25},
            onRemove: (_) async {},
          ),
        ),
      ),
    );
    expect(find.text('+1.25%'), findsOneWidget);
  });

  testWidgets(
    'swiping left reveals the delete button and tapping it calls onRemove',
    (tester) async {
      final removed = <Map<String, dynamic>>[];
      await pumpRow(tester, removed);

      await tester.fling(find.text('天弘纳斯达克100指数发起(QDII)A'), const Offset(-500, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('删除'), findsOneWidget);

      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(removed, [fund]);
    },
  );

  testWidgets('a plain tap never removes the fund', (tester) async {
    final removed = <Map<String, dynamic>>[];
    await pumpRow(tester, removed);

    await tester.tap(find.text('天弘纳斯达克100指数发起(QDII)A'));
    await tester.pumpAndSettle();

    expect(find.text('删除基金'), findsNothing);
    expect(removed, isEmpty);
  });
}
