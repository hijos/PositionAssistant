import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:position_assistant/data/fund_repository.dart';
import 'package:position_assistant/fund_search.dart';

void main() {
  final fund = {'code': '000001', 'name': '测试基金A', 'type': '混合型'};
  test('remote repository sends only code with current credential and handles expiry', () async {
    var status = 200;
    final repo = RemoteFundRepository(
      token: 'session-a',
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer session-a');
        expect(request.url.path, '/api/my-funds');
        if (request.method == 'POST') {
          expect(jsonDecode(request.body), {'code': '000001'});
        }
        return http.Response(
          jsonEncode(request.method == 'GET' ? [fund] : fund),
          status,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    expect(await repo.add({...fund, 'userId': 'forged'}), fund);
    expect(await repo.list(), [fund]);
    status = 401;
    await expectLater(repo.add(fund), throwsException);
    repo.close();
  });
  testWidgets(
    'adding disables repeat taps; failure permits retry and success is visible',
    (tester) async {
      var pending = Completer<Map<String, dynamic>>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: FundSearchPage(
            sourceLabel: '本地模式',
            search: (_) async => [fund],
            add: (_) {
              calls++;
              return pending.future;
            },
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '000001');
      await tester.tap(find.text('搜索'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加'));
      await tester.pump();
      expect(find.text('添加中'), findsOneWidget);
      expect(calls, 1);
      pending.completeError(Exception('offline'));
      await tester.pumpAndSettle();
      expect(find.text('添加失败，请检查登录或网络后重试'), findsOneWidget);
      pending = Completer();
      await tester.tap(find.text('添加'));
      await tester.pump();
      pending.complete(fund);
      await tester.pumpAndSettle();
      expect(find.text('已添加'), findsOneWidget);
      expect(calls, 2);
    },
  );
}
