import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:position_assistant/data/transaction_repository.dart';
import 'package:position_assistant/transaction_entry.dart';

class FakeTransactionRepository implements TransactionRepository {
  Map<String, dynamic>? lastPreview;
  Map<String, dynamic>? lastCreate;

  @override
  Future<void> close() async {}

  @override
  Future<Map<String, dynamic>> create(Map<String, dynamic> draft) async {
    lastCreate = normalizeTransaction(draft);
    return {...draft, 'status': 'pending'};
  }

  @override
  Future<List<Map<String, dynamic>>> list() async => [];

  @override
  Future<List<Map<String, dynamic>>> confirmPending() async => [];

  @override
  Future<Map<String, dynamic>> cancel(String id) async => {'id': id};

  @override
  Future<void> deleteCancelled(String id) async {}

  @override
  Future<int> clearCancelled() async => 0;

  @override
  Future<Map<String, dynamic>> preview(Map<String, dynamic> draft) async {
    lastPreview = draft;
    return {...draft, 'status': 'pending', 'pendingReason': '等待正式净值'};
  }
}

void main() {
  final fund = {'code': '000001', 'name': '测试基金A', 'type': '混合型'};
  final draft = {
    'fundCode': '000001',
    'fundName': '测试基金A',
    'fundType': '混合型',
    'entryMode': 'amount',
    'amount': 100,
    'shares': 0,
    'feeMode': 'rate',
    'feeRate': 0.15,
    'fixedFee': 0,
    'date': '2026-09-24',
    'cutoff': 'before',
  };

  test('normalizes a buy draft and rejects unsupported direction', () {
    final normalized = normalizeBuy(draft);
    expect(normalized['type'], 'buy');
    expect(normalized['amount'], 100);
    expect(normalized['feeRate'], 0.15);
    expect(
      () => normalizeBuy({...draft, 'type': 'sell'}),
      throwsFormatException,
    );
    expect(() => normalizeBuy({...draft, 'amount': 0}), throwsFormatException);
  });

  test(
    'normalizes a sell draft and keeps the direction for remote requests',
    () {
      final normalized = normalizeTransaction({...draft, 'type': 'sell'});
      expect(normalized['type'], 'sell');
      expect(normalized['amount'], 100);
    },
  );

  test(
    'remote repository sends authenticated preview and create requests',
    () async {
      final paths = <String>[];
      final requests = <Map<String, dynamic>>[];
      final repo = RemoteTransactionRepository(
        token: 'session-a',
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer session-a');
          paths.add(request.url.path);
          if (request.body.isNotEmpty) {
            requests.add(jsonDecode(request.body) as Map<String, dynamic>);
          }
          return http.Response(
            jsonEncode(
              request.method == 'DELETE'
                  ? {'id': 'tx-1', 'status': 'cancelled'}
                  : request.url.path.endsWith('/confirm')
                  ? {'ok': true, 'transactions': []}
                  : {...draft, 'status': 'pending'},
            ),
            request.method == 'DELETE' || request.url.path.endsWith('/preview')
                ? 200
                : 201,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await repo.preview(draft);
      await repo.create(draft);
      await repo.confirmPending();
      final cancelled = await repo.cancel('tx-1');
      expect(paths, [
        '/api/transactions/preview',
        '/api/transactions',
        '/api/transactions/confirm',
        '/api/transactions/tx-1',
      ]);
      expect(cancelled['status'], 'cancelled');
      expect(requests.first['type'], 'buy');
      expect(requests.first['fundName'], '测试基金A');
      await repo.close();
    },
  );

  test(
    'remote repository calls the permanent delete and bulk clear endpoints',
    () async {
      final calls = <String>[];
      final repo = RemoteTransactionRepository(
        token: 'session-a',
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer session-a');
          calls.add('${request.method} ${request.url.path}');
          return http.Response(
            jsonEncode(
              request.url.path.endsWith('/cancelled')
                  ? {'ok': true, 'deleted': 3}
                  : {'ok': true, 'id': 'tx-9'},
            ),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await repo.deleteCancelled('tx-9');
      expect(await repo.clearCancelled(), 3);
      expect(calls, [
        'DELETE /api/transactions/tx-9/permanent',
        'DELETE /api/transactions/cancelled',
      ]);
      await expectLater(
        repo.deleteCancelled('  '),
        throwsA(isA<FormatException>()),
      );
      expect(calls, hasLength(2));
      await repo.close();
    },
  );

  testWidgets('buy entry previews and saves a selected fund', (tester) async {
    final repo = FakeTransactionRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: TransactionEntryPage(funds: [fund], repository: repo),
      ),
    );
    expect(find.text('交易录入'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('预览买入'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('预览买入'));
    await tester.pumpAndSettle();
    expect(find.text('买入预览'), findsOneWidget);
    expect(repo.lastPreview?['fundCode'], '000001');
    await tester.scrollUntilVisible(
      find.text('保存买入'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('保存买入'));
    await tester.pumpAndSettle();
    expect(repo.lastCreate?['type'], 'buy');
  });

  testWidgets('buy entry can add a fund and selects the newly added fund', (
    tester,
  ) async {
    final repo = FakeTransactionRepository();
    final addedFund = {'code': '000002', 'name': '刚添加基金B', 'type': '股票型'};
    await tester.pumpWidget(
      MaterialApp(
        home: TransactionEntryPage(
          funds: [fund],
          repository: repo,
          onSearchAndAdd: () async => [fund, addedFund],
        ),
      ),
    );
    expect(find.text('搜索基金并添加到自选列表'), findsOneWidget);
    await tester.tap(find.text('搜索基金并添加到自选列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    expect(find.text('刚添加基金B · 000002'), findsNWidgets(2));
  });

  testWidgets('sell entry exposes sell labels and sends sell direction', (
    tester,
  ) async {
    final repo = FakeTransactionRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: TransactionEntryPage(
          funds: [fund],
          repository: repo,
          initialType: 'sell',
        ),
      ),
    );
    expect(find.text('交易录入'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('保存卖出'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('保存卖出'));
    await tester.pumpAndSettle();
    expect(repo.lastCreate?['type'], 'sell');
  });
}
