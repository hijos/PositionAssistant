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
    expect(find.byIcon(Icons.delete_outline), findsNothing);
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
    'long press opens the delete sheet and cancelling keeps the fund',
    (tester) async {
      final removed = <Map<String, dynamic>>[];
      await pumpRow(tester, removed);

      await tester.longPress(find.text('天弘纳斯达克100指数发起(QDII)A'));
      await tester.pumpAndSettle();
      expect(find.text('删除基金'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('删除基金'), findsNothing);
      expect(removed, isEmpty);
    },
  );

  testWidgets('picking the sheet action removes the long-pressed fund', (
    tester,
  ) async {
    final removed = <Map<String, dynamic>>[];
    await pumpRow(tester, removed);

    await tester.longPress(find.byType(FundListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除基金'));
    await tester.pumpAndSettle();

    expect(removed, [fund]);
  });

  testWidgets('a plain tap never removes the fund', (tester) async {
    final removed = <Map<String, dynamic>>[];
    await pumpRow(tester, removed);

    await tester.tap(find.text('天弘纳斯达克100指数发起(QDII)A'));
    await tester.pumpAndSettle();

    expect(find.text('删除基金'), findsNothing);
    expect(removed, isEmpty);
  });
}
