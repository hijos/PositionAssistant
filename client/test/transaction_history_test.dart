import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:position_assistant/data/transaction_repository.dart';
import 'package:position_assistant/transaction_history.dart';

class HistoryRepository implements TransactionRepository {
  HistoryRepository(this.records);

  final List<Map<String, dynamic>> records;

  @override
  Future<void> close() async {}

  @override
  Future<Map<String, dynamic>> create(Map<String, dynamic> draft) async =>
      draft;

  @override
  Future<List<Map<String, dynamic>>> confirmPending() async => records;

  @override
  Future<Map<String, dynamic>> cancel(String id) async {
    final item = records.firstWhere((record) => record['id'] == id);
    item['status'] = 'cancelled';
    item['cancelledAt'] = '2026-09-24T10:00:00Z';
    return item;
  }

  @override
  Future<List<Map<String, dynamic>>> list() async => records;

  @override
  Future<Map<String, dynamic>> preview(Map<String, dynamic> draft) async =>
      draft;
}

Map<String, dynamic> record({
  required String id,
  required String date,
  String status = 'confirmed',
  String type = 'buy',
}) => {
  'id': id,
  'fundCode': '000001',
  'fundName': '测试基金A',
  'fundType': '混合型',
  'type': type,
  'entryMode': 'amount',
  'amount': 100,
  'shares': 22.5,
  'feeMode': 'rate',
  'feeRate': 0.15,
  'fixedFee': 0,
  'fee': 0.15,
  'date': date,
  'cutoff': 'before',
  'tradeNav': 4.42,
  'navDate': '2026-09-24',
  'status': status,
  'pendingReason': status == 'pending' ? '等待正式净值' : null,
  'note': '月度买入',
  'source': '手工录入',
  'createdAt': '2026-09-24T09:00:00Z',
};

void main() {
  test('sorts newest transaction first and puts after-15:00 later', () {
    final records = [
      record(id: 'old', date: '2026-09-20'),
      record(id: 'new', date: '2026-09-24'),
    ];
    expect(sortTransactions(records).map((item) => item['id']), ['new', 'old']);
  });

  testWidgets('opens a complete detail page from a transaction row', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TransactionHistoryPage(
          repository: HistoryRepository([
            record(id: 'confirmed', date: '2026-09-24'),
            record(
              id: 'pending',
              date: '2026-09-23',
              status: 'pending',
              type: 'sell',
            ),
            record(id: 'cancelled', date: '2026-09-22', status: 'cancelled'),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('已确认'), findsOneWidget);
    expect(find.text('待确认'), findsOneWidget);
    expect(find.text('已取消'), findsOneWidget);
    await tester.tap(find.text('测试基金A · 买入').first);
    await tester.pumpAndSettle();
    expect(find.text('交易详情'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('成交净值'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('成交净值'), findsOneWidget);
    expect(find.text('4.42'), findsOneWidget);
    expect(find.text('月度买入'), findsOneWidget);
    expect(find.text('手工录入'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('撤销交易'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('撤销交易'));
    await tester.pumpAndSettle();
    expect(find.text('交易记录'), findsOneWidget);
  });
}
