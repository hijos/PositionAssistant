import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:position_assistant/fund_search.dart';

void main() {
  test('API encodes query and rejects unavailable responses', () async {
    final api = FundSearchApi(
      client: MockClient((request) async {
        expect(request.url.path, '/api/funds/search');
        expect(request.url.queryParameters['q'], '测试 A');
        return http.Response('[]', 200);
      }),
    );
    expect(await api.search('测试 A'), isEmpty);
    api.close();
    final failed = FundSearchApi(
      client: MockClient((_) async => http.Response('{}', 503)),
    );
    await expectLater(failed.search('a'), throwsException);
    failed.close();
  });
  testWidgets(
    'search renders loading, results, empty state and retryable failure',
    (tester) async {
      var pending = Completer<List<Map<String, dynamic>>>();
      await tester.pumpWidget(
        MaterialApp(home: FundSearchPage(search: (_) => pending.future)),
      );
      await tester.enterText(find.byType(TextField), '测试');
      await tester.tap(find.text('搜索'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      pending.complete([
        {'code': '000001', 'name': '测试基金', 'type': '混合型'},
      ]);
      await tester.pumpAndSettle();
      expect(find.text('测试基金'), findsOneWidget);
      pending = Completer();
      await tester.tap(find.text('搜索'));
      await tester.pump();
      pending.complete([]);
      await tester.pumpAndSettle();
      expect(find.text('没有找到符合条件的基金'), findsOneWidget);
      pending = Completer();
      await tester.tap(find.text('搜索'));
      await tester.pump();
      pending.completeError(Exception());
      await tester.pumpAndSettle();
      expect(find.text('基金搜索暂时不可用，请稍后重试'), findsOneWidget);
    },
  );
  testWidgets(
    'editing query discards stale responses and blank queries do not fetch',
    (tester) async {
      final pending = Completer<List<Map<String, dynamic>>>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: FundSearchPage(
            search: (_) {
              calls++;
              return pending.future;
            },
          ),
        ),
      );
      await tester.tap(find.text('搜索'));
      await tester.pump();
      expect(calls, 0);
      await tester.enterText(find.byType(TextField), '旧');
      await tester.tap(find.text('搜索'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '新');
      pending.complete([
        {'code': '000001', 'name': '旧结果', 'type': '混合型'},
      ]);
      await tester.pumpAndSettle();
      expect(find.text('旧结果'), findsNothing);
    },
  );
}
