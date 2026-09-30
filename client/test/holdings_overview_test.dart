import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:position_assistant/main.dart';

const double _k320 = 320;
const double _k1280 = 1280;

/// A single fund position as the repositories return it.
Map<String, dynamic> holding({
  String fundCode = '539001',
  String fundName = '建信纳斯达克100指数（QDII）A人民币',
  double shares = 310.96,
  double cost = 1050,
  double? marketValue = 1093.74,
  double? profit = 43.74,
  double? profitRate = 0.041657,
  double? estimatedMarketValue,
  double? estimatedProfit,
  double? estimatedProfitRate,
}) => {
  'fundCode': fundCode,
  'fundName': fundName,
  'shares': shares,
  'cost': cost,
  'marketValue': marketValue,
  'profit': profit,
  'profitRate': profitRate,
  'estimatedMarketValue': estimatedMarketValue,
  'estimatedProfit': estimatedProfit,
  'estimatedProfitRate': estimatedProfitRate,
};

/// The overview figures used across these tests.
const overviewData = HoldingOverviewState.ready(
  HoldingOverviewData(
    totalMarketValue: 2106.56,
    totalProfit: 56.1,
    totalProfitRate: 0.027384,
    totalEstimatedMarketValue: 2140.2,
    totalEstimatedProfit: 89.74,
    totalEstimatedProfitRate: 0.0438,
  ),
);

/// `2106.56` -> `￥2106.56`, mirroring the production formatter.
String money(String amount) => '￥$amount';

void _useViewport(WidgetTester tester, double width, {double height = 640}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Pumps [child] at the top-left of a screen-sized box so that any overflow is
/// reported by the test binding.
Future<void> pumpFullWidth(
  WidgetTester tester,
  Widget child,
  double width,
) async {
  _useViewport(tester, width);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(alignment: Alignment.topLeft, child: child),
      ),
    ),
  );
}

/// Rebuilds the home page layout: a 16px gutter around a 960px-wide column.
Future<void> pumpPageColumn(
  WidgetTester tester,
  List<Widget> children,
  double width,
) async {
  _useViewport(tester, width, height: 800);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: children,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('overview card fills the available width at 320 and 1280', (
    tester,
  ) async {
    for (final width in [_k320, _k1280]) {
      await pumpFullWidth(
        tester,
        const HoldingOverviewCard(state: overviewData),
        width,
      );
      // No fixed width, no square aspect ratio: the card spans the viewport.
      expect(
        tester.getSize(find.byType(HoldingOverviewCard)).width,
        width,
        reason: 'card width at $width',
      );
      expect(tester.takeException(), isNull, reason: 'layout at $width');
    }
  });

  testWidgets('overview card shows the four labelled rows', (tester) async {
    await pumpFullWidth(
      tester,
      const HoldingOverviewCard(state: overviewData),
      _k320,
    );
    expect(find.text('持仓概览'), findsOneWidget);
    expect(find.text('总市值'), findsOneWidget);
    expect(find.text('总收益'), findsOneWidget);
    expect(find.text('预估市值'), findsOneWidget);
    expect(find.text('预估收益'), findsOneWidget);
    // Amounts keep two decimals and rates use Chinese parentheses.
    expect(find.text(money('2106.56')), findsOneWidget);
    expect(find.text('${money('56.10')}（2.74%）'), findsOneWidget);
    expect(find.text(money('2140.20')), findsOneWidget);
    expect(find.text('${money('89.74')}（4.38%）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('estimate explanation dialog opens from the info icon', (
    tester,
  ) async {
    await pumpFullWidth(
      tester,
      const HoldingOverviewCard(state: overviewData),
      _k320,
    );
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();
    expect(find.text('预估收益说明'), findsOneWidget);
    expect(find.text('根据美股最新数据估算'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.text('根据美股最新数据估算'), findsNothing);
  });

  testWidgets('overview shows — instead of 0 when data is missing', (
    tester,
  ) async {
    await pumpFullWidth(
      tester,
      const HoldingOverviewCard(
        state: HoldingOverviewState.ready(HoldingOverviewData.empty),
      ),
      _k320,
    );
    expect(find.text('—'), findsNWidgets(4));
    expect(find.textContaining(money('0.00')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('overview keeps a real zero distinct from missing data', (
    tester,
  ) async {
    await pumpFullWidth(
      tester,
      const HoldingOverviewCard(
        state: HoldingOverviewState.ready(_ZeroOverview()),
      ),
      _k320,
    );
    // Both value rows and both profit rows render a real ￥0.00, not a dash.
    expect(find.text(money('0.00')), findsNWidgets(2));
    expect(find.text('${money('0.00')}（0.00%）'), findsNWidgets(2));
    expect(find.text('—'), findsNothing);
  });

  testWidgets('overview stays full width while loading and on failure', (
    tester,
  ) async {
    await pumpFullWidth(
      tester,
      const HoldingOverviewCard(state: HoldingOverviewState.loading()),
      _k320,
    );
    expect(find.text('持仓概览'), findsOneWidget);
    expect(find.text('正在读取…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.getSize(find.byType(HoldingOverviewCard)).width, _k320);

    var retried = false;
    await pumpFullWidth(
      tester,
      HoldingOverviewCard(
        state: const HoldingOverviewState.error('持仓读取失败，请重试'),
        onRetry: () => retried = true,
      ),
      _k320,
    );
    expect(find.text('持仓概览'), findsOneWidget);
    expect(find.text('持仓读取失败，请重试'), findsOneWidget);
    expect(tester.getSize(find.byType(HoldingOverviewCard)).width, _k320);
    await tester.tap(find.text('重试'));
    expect(retried, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('page column keeps the card stretched to the full gutter width', (
    tester,
  ) async {
    for (final entry in {_k320: 288.0, _k1280: 928.0}.entries) {
      await pumpPageColumn(tester, [
        const HoldingOverviewCard(state: overviewData),
        HoldingListItem(item: holding(), onTap: () {}),
      ], entry.key);
      final width = tester.getSize(find.byType(HoldingOverviewCard)).width;
      expect(width, entry.value, reason: 'card width at ${entry.key}');
      expect(width, greaterThan(240), reason: 'not a narrow square card');
      expect(tester.takeException(), isNull, reason: 'page at ${entry.key}');
    }
  });

  testWidgets('fund row shows name, shares, cost, value, profit and estimate', (
    tester,
  ) async {
    await pumpFullWidth(
      tester,
      HoldingListItem(
        item: holding(
          estimatedMarketValue: 1120.5,
          estimatedProfit: 70.5,
          estimatedProfitRate: 0.067143,
        ),
        onTap: () {},
      ),
      _k320,
    );
    expect(find.text('建信纳斯达克100指数（QDII）A人民币'), findsOneWidget);
    expect(find.text('539001  310.96份'), findsOneWidget);
    expect(find.text('成本 ${money('1050.00')}'), findsOneWidget);
    expect(find.text(money('1093.74')), findsOneWidget);
    expect(find.text('${money('43.74')}（4.17%）'), findsOneWidget);
    expect(find.text('预估 ${money('70.50')}（6.71%）'), findsOneWidget);
    // The redundant wording removed by this change.
    expect(find.textContaining('正式收益'), findsNothing);
    expect(find.textContaining('正式市值'), findsNothing);
    expect(find.textContaining('暂无有效估算'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fund name ellipsizes on one line instead of wrapping', (
    tester,
  ) async {
    const fundName = '建信纳斯达克100指数（QDII）A人民币';
    await pumpFullWidth(
      tester,
      HoldingListItem(item: holding(), onTap: () {}),
      _k320,
    );
    final name = tester.widget<Text>(find.text(fundName));
    expect(name.maxLines, 1);
    expect(name.overflow, TextOverflow.ellipsis);
    // The right-hand column keeps its width, so the name is what gives way.
    expect(tester.getSize(find.text(fundName)).width, lessThan(_k320 - 132));
    expect(tester.takeException(), isNull);
  });

  testWidgets('market value is larger than the profit figure', (tester) async {
    await pumpFullWidth(
      tester,
      HoldingListItem(item: holding(), onTap: () {}),
      _k320,
    );
    final valueSize = tester
        .widget<Text>(find.text(money('1093.74')))
        .style!
        .fontSize!;
    final profitSize = tester
        .widget<Text>(find.text('${money('43.74')}（4.17%）'))
        .style!
        .fontSize!;
    expect(valueSize, greaterThan(profitSize));
  });

  testWidgets('overview total is as large as a fund market value', (
    tester,
  ) async {
    await pumpPageColumn(tester, [
      const HoldingOverviewCard(state: overviewData),
      HoldingListItem(item: holding(), onTap: () {}),
    ], _k320);
    final totalSize = tester
        .widget<Text>(find.text(money('2106.56')))
        .style!
        .fontSize!;
    final fundSize = tester
        .widget<Text>(find.text(money('1093.74')))
        .style!
        .fontSize!;
    expect(totalSize, fundSize);
  });

  testWidgets('estimate icon leads the label instead of trailing the row', (
    tester,
  ) async {
    await pumpFullWidth(
      tester,
      const HoldingOverviewCard(state: overviewData),
      _k320,
    );
    final icon = find.byIcon(Icons.info_outline);
    final label = find.text('预估收益');
    final value = find.text('${money('89.74')}（4.38%）');
    expect(icon, findsOneWidget);
    // Icon, then label, then the value: left to right in that order.
    expect(tester.getTopLeft(icon).dx, lessThan(tester.getTopLeft(label).dx));
    expect(tester.getTopLeft(label).dx, lessThan(tester.getTopLeft(value).dx));
    // The icon is bounded to one touch target, so the 预估收益 label starts at
    // most that far right of the other labels rather than drifting away.
    final column = tester.getTopLeft(find.text('总市值')).dx;
    final shift = tester.getTopLeft(label).dx - column;
    expect(shift, greaterThanOrEqualTo(0));
    expect(shift, lessThanOrEqualTo(kMinInteractiveDimension));
    // The icon is still comfortably tappable at 320px width.
    expect(tester.getSize(find.byType(IconButton)), const Size(48, 48));
    // Nothing overflows: the long rate value still fits beside the label.
    expect(
      tester.getTopRight(value).dx,
      lessThanOrEqualTo(
        tester.getTopRight(find.byType(HoldingOverviewCard)).dx,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('gains are red and losses green (CN market convention)', (
    tester,
  ) async {
    await pumpFullWidth(
      tester,
      Column(
        children: [
          HoldingListItem(
            item: holding(fundCode: '000001', fundName: '盈利基金'),
            onTap: () {},
          ),
          HoldingListItem(
            item: holding(
              fundCode: '000002',
              fundName: '亏损基金',
              cost: 1000,
              marketValue: 900,
              profit: -100,
              profitRate: -0.1,
            ),
            onTap: () {},
          ),
        ],
      ),
      _k320,
    );
    final gain = tester
        .widget<Text>(find.text('${money('43.74')}（4.17%）'))
        .style!
        .color;
    final loss = tester
        .widget<Text>(find.text('${money('-100.00')}（-10.00%）'))
        .style!
        .color;
    expect(gain, Colors.red.shade700);
    expect(loss, Colors.green.shade700);
    expect(gain, isNot(loss));
    expect(tester.takeException(), isNull);
  });

  testWidgets('consecutive fund rows keep a tight vertical rhythm', (
    tester,
  ) async {
    final first = holding(fundCode: '000001', fundName: '第一只基金');
    final second = holding(fundCode: '000002', fundName: '第二只基金');
    await pumpFullWidth(
      tester,
      Column(
        children: [
          HoldingListItem(item: first, onTap: () {}),
          HoldingListItem(item: second, onTap: () {}),
        ],
      ),
      _k320,
    );
    final rows = find.byType(HoldingListItem);
    expect(rows, findsNWidgets(2));
    // Rows sit back to back (each carries only 8px of its own padding), which
    // is markedly denser than the previous 14px list-tile spacing.
    final gap =
        tester.getTopLeft(rows.at(1)).dy - tester.getBottomLeft(rows.at(0)).dy;
    expect(gap, lessThanOrEqualTo(1));
    // Height in the test font (Ahem line boxes are tall); what matters is that
    // the rows touch instead of leaving a tile's worth of gap between them.
    expect(tester.getSize(rows.at(0)).height, lessThan(94));
    expect(tester.takeException(), isNull);
  });

  testWidgets('fund row without an estimate shows 预估 —', (tester) async {
    await pumpFullWidth(
      tester,
      HoldingListItem(item: holding(), onTap: () {}),
      _k320,
    );
    expect(find.text('预估 —'), findsOneWidget);
    expect(find.text('${money('43.74')}（4.17%）'), findsOneWidget);
  });

  testWidgets('formal data missing renders dashes, never zeros', (
    tester,
  ) async {
    await pumpFullWidth(
      tester,
      HoldingListItem(
        item: holding(marketValue: null, profit: null, profitRate: null),
        onTap: () {},
      ),
      _k320,
    );
    // Market value and profit are missing, so both render a dash rather than
    // ￥0.00, while the estimator is simply absent.
    expect(find.text('—'), findsNWidgets(2));
    expect(find.text(money('0.00')), findsNothing);
    expect(find.text('预估 —'), findsOneWidget);
  });
}

/// A real `0` return, which must not be mistaken for missing data.
class _ZeroOverview extends HoldingOverviewData {
  const _ZeroOverview()
    : super(
        totalMarketValue: 0,
        totalProfit: 0,
        totalProfitRate: 0,
        totalEstimatedMarketValue: 0,
        totalEstimatedProfit: 0,
        totalEstimatedProfitRate: 0,
      );
}
