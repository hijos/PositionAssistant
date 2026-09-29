import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:position_assistant/data/transaction_repository.dart';
import 'package:position_assistant/holding_detail.dart';

class DetailRepository implements TransactionRepository {
  DetailRepository(this.records);
  final List<Map<String, dynamic>> records;

  @override
  Future<void> close() async {}

  @override
  Future<Map<String, dynamic>> cancel(String id) async =>
      records.firstWhere((item) => item['id'] == id);

  @override
  Future<void> deleteCancelled(String id) async =>
      records.removeWhere((item) => item['id'] == id);

  @override
  Future<int> clearCancelled() async {
    final removed = records
        .where((item) => item['status'] == 'cancelled')
        .length;
    records.removeWhere((item) => item['status'] == 'cancelled');
    return removed;
  }

  @override
  Future<List<Map<String, dynamic>>> confirmPending() async => records;

  @override
  Future<Map<String, dynamic>> create(Map<String, dynamic> draft) async =>
      draft;

  @override
  Future<List<Map<String, dynamic>>> list() async => records;

  @override
  Future<Map<String, dynamic>> preview(Map<String, dynamic> draft) async =>
      draft;
}

Map<String, dynamic> tx(String id, String code, String status) => {
  'id': id,
  'fundCode': code,
  'fundName': code == '000001' ? '测试基金A' : '其他基金',
  'fundType': '混合型',
  'type': 'buy',
  'entryMode': 'amount',
  'amount': 100,
  'shares': 20,
  'fee': 0,
  'date': '2026-09-24',
  'cutoff': 'before',
  'status': status,
  'pendingReason': '等待正式净值',
};

void main() {
  testWidgets('holding detail shows summary and only associated transactions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HoldingDetailPage(
          holding: {
            'fundCode': '000001',
            'fundName': '测试基金A',
            'shares': 20,
            'invested': 100,
            'redeemed': 0,
            'cost': 100,
            'realizedProfit': 0,
            'nav': 5,
            'navDate': '2026-09-24',
            'marketValue': 100,
            'profit': 0,
            'profitRate': 0,
          },
          repository: DetailRepository([
            tx('matching', '000001', 'confirmed'),
            tx('pending', '000001', 'pending'),
            tx('other', '000002', 'confirmed'),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('剩余持仓成本'), findsOneWidget);
    expect(find.text('关联交易'), findsOneWidget);
    expect(find.text('待确认'), findsOneWidget);
    expect(find.text('其他基金'), findsNothing);
    expect(find.text('测试基金A'), findsOneWidget);
  });

  testWidgets('empty holding selection explains there is no position', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HoldingSelectionPage(
          holdings: [],
          repository: _EmptyRepository(),
        ),
      ),
    );
    expect(find.text('暂无持仓'), findsOneWidget);
  });
}

class _EmptyRepository extends DetailRepository {
  _EmptyRepository() : super([]);
}
