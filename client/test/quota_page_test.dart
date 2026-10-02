import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:position_assistant/data/quota_repository.dart';
import 'package:position_assistant/quota_page.dart';

class _FakeQuotaRepository implements QuotaRepository {
  _FakeQuotaRepository(this.items);
  final List<Quota> items;
  @override Future<List<Quota>> list() async => items;
  @override Future<List<Quota>> refresh() async => items;
  @override Future<void> setOverride(String code, Quota fields) async {}
  @override Future<void> restore(String code) async {}
  @override Future<QuotaUploadResult> uploadCorrection(String code, Quota fields) async => throw UnimplementedError();
}

Quota _quota(String code, String name, {double? direct, double? distribution}) => {
      'code': code,
      'name': name,
      'category': '纳斯达克100',
      'channels': {
        'direct': {'status': '限大额', 'limit': direct},
        'distribution': {'status': '限大额', 'limit': distribution},
      },
    };

double _top(WidgetTester tester, String name) => tester.getTopLeft(find.text(name)).dy;

void main() {
  Future<void> pumpPage(WidgetTester tester, List<Quota> items) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: QuotaPage(repository: _FakeQuotaRepository(items)))));
    await tester.pump();
  }

  testWidgets('quota order takes priority over family grouping', (tester) async {
    await pumpPage(tester, [
      _quota('100001', '招商纳斯达克100ETF发起式联接(QDII)A', direct: 100),
      _quota('100002', '招商纳斯达克100ETF发起式联接(QDII)C', direct: 500),
      _quota('100003', '大成纳斯达克100ETF联接(QDII)A', direct: 300),
    ]);
    // Descending direct quota remains the primary order: C(500), 大成A(300), A(100).
    expect(_top(tester, '招商纳斯达克100ETF发起式联接(QDII)C'), lessThan(_top(tester, '大成纳斯达克100ETF联接(QDII)A')));
    expect(_top(tester, '大成纳斯达克100ETF联接(QDII)A'), lessThan(_top(tester, '招商纳斯达克100ETF发起式联接(QDII)A')));
  });

  testWidgets('equal quota share classes stay adjacent with A first', (tester) async {
    await pumpPage(tester, [
      _quota('100001', '招商纳斯达克100ETF发起式联接(QDII)A', direct: 300),
      _quota('100002', '招商纳斯达克100ETF发起式联接(QDII)C', direct: 300),
      _quota('100003', '招商纳斯达克100ETF发起式联接(QDII)D', direct: 300),
      _quota('100004', '大成纳斯达克100ETF联接(QDII)A', direct: 200),
    ]);
    final a = _top(tester, '招商纳斯达克100ETF发起式联接(QDII)A');
    final c = _top(tester, '招商纳斯达克100ETF发起式联接(QDII)C');
    final d = _top(tester, '招商纳斯达克100ETF发起式联接(QDII)D');
    expect(a, lessThan(c));
    expect(c, lessThan(d));
    expect(d - a, lessThan(250));
    expect(d, lessThan(_top(tester, '大成纳斯达克100ETF联接(QDII)A')));
  });

  testWidgets('排除C hides C-class funds only', (tester) async {
    await pumpPage(tester, [
      _quota('100001', '招商纳斯达克100ETF发起式联接(QDII)A', direct: 100),
      _quota('100002', '招商纳斯达克100ETF发起式联接(QDII)C', direct: 500),
    ]);
    expect(find.text('招商纳斯达克100ETF发起式联接(QDII)C'), findsOneWidget);
    await tester.tap(find.text('排除C'));
    await tester.pump();
    expect(find.text('招商纳斯达克100ETF发起式联接(QDII)A'), findsOneWidget);
    expect(find.text('招商纳斯达克100ETF发起式联接(QDII)C'), findsNothing);
    await tester.tap(find.text('排除C'));
    await tester.pump();
    expect(find.text('招商纳斯达克100ETF发起式联接(QDII)C'), findsOneWidget);
  });

  testWidgets('按最大额度 sorts by the larger of direct and distribution', (tester) async {
    await pumpPage(tester, [
      _quota('100004', '易方达纳斯达克100ETF联接(QDII-LOF)A(人民币)', direct: 50, distribution: 400),
      _quota('100005', '南方纳斯达克100指数发起(QDII)A', direct: 300, distribution: 10),
    ]);
    // Default 按直销额度: 南方 (300) ahead of 易方达 (50).
    expect(_top(tester, '南方纳斯达克100指数发起(QDII)A'), lessThan(_top(tester, '易方达纳斯达克100ETF联接(QDII-LOF)A(人民币)')));
    await tester.tap(find.text('按直销额度'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('按最大额度').last);
    await tester.pumpAndSettle();
    // 按最大额度: 易方达 (max 400) ahead of 南方 (max 300).
    expect(_top(tester, '易方达纳斯达克100ETF联接(QDII-LOF)A(人民币)'), lessThan(_top(tester, '南方纳斯达克100指数发起(QDII)A')));
    // Only the channel carrying the larger limit is bolded.
    Text valueText(String text) => tester.widget<Text>(find.text(text));
    expect(valueText('400').style?.fontWeight, FontWeight.w700);
    expect(valueText('50').style?.fontWeight, isNot(FontWeight.w700));
    expect(valueText('300').style?.fontWeight, FontWeight.w700);
    expect(valueText('10').style?.fontWeight, isNot(FontWeight.w700));
  });
}
