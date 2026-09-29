import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:position_assistant/data/transaction_repository.dart';
import 'package:position_assistant/transaction_history.dart';

class HistoryRepository implements TransactionRepository {
  HistoryRepository(this.records, {this.failDeletes = false});

  final List<Map<String, dynamic>> records;
  final bool failDeletes;
  int deleteCalls = 0;
  int clearCalls = 0;
  String? lastDeletedId;

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
  Future<void> deleteCancelled(String id) async {
    deleteCalls++;
    if (failDeletes) throw Exception('记录不存在');
    final target = records.firstWhere((record) => record['id'] == id);
    if (target['status'] != 'cancelled') {
      throw const FormatException('只能删除已取消交易，请先撤销该交易');
    }
    lastDeletedId = id;
    records.removeWhere((record) => record['id'] == id);
  }

  @override
  Future<int> clearCancelled() async {
    clearCalls++;
    if (failDeletes) throw Exception('清理失败');
    final removed = records
        .where((record) => record['status'] == 'cancelled')
        .length;
    records.removeWhere((record) => record['status'] == 'cancelled');
    return removed;
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
  String fundCode = '000001',
  String fundName = '测试基金A',
}) => {
  'id': id,
  'fundCode': fundCode,
  'fundName': fundName,
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

Widget page(TransactionRepository repository, {String? fundCode}) =>
    MaterialApp(
      home: TransactionHistoryPage(repository: repository, fundCode: fundCode),
    );

Finder cleanupButton() => find.ancestor(
  of: find.byIcon(Icons.delete_sweep_outlined),
  matching: find.byType(IconButton),
);

bool cleanupEnabled(WidgetTester tester) =>
    tester.widget<IconButton>(cleanupButton()).onPressed != null;

Future<void> openDeleteMenu(WidgetTester tester, String title) async {
  await tester.longPress(find.text(title));
  await tester.pumpAndSettle();
}

Future<void> openDetail(WidgetTester tester, String title) async {
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

/// Confirms the permanent-delete dialog by tapping its destructive action.
Future<void> confirmDeleteDialog(WidgetTester tester, String title) async {
  expect(find.text(title), findsOneWidget);
  await tester.tap(find.text('删除'));
  await tester.pump();
}

/// Pumps until [message] shows up: a SnackBar keeps its own dismiss timer, so
/// pumpAndSettle can run past the frame in which it is visible.
Future<void> expectSnack(WidgetTester tester, String message) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (find.text(message).evaluate().isNotEmpty) break;
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(find.text(message), findsWidgets);
}

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
      page(
        HistoryRepository([
          record(id: 'confirmed', date: '2026-09-24'),
          record(
            id: 'pending',
            date: '2026-09-23',
            status: 'pending',
            type: 'sell',
          ),
          record(
            id: 'cancelled',
            date: '2026-09-22',
            status: 'cancelled',
            type: 'sell',
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('已确认'), findsOneWidget);
    expect(find.text('待确认'), findsOneWidget);
    expect(find.text('已取消'), findsOneWidget);
    await openDetail(tester, '测试基金A · 买入');
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

  testWidgets('cleanup button stays disabled until a cancelled record exists', (
    tester,
  ) async {
    final repository = HistoryRepository([
      record(id: 'confirmed', date: '2026-09-24'),
      record(
        id: 'pending',
        date: '2026-09-23',
        status: 'pending',
        type: 'sell',
      ),
    ]);
    await tester.pumpWidget(page(repository));
    await tester.pumpAndSettle();
    expect(cleanupButton(), findsOneWidget);
    expect(cleanupEnabled(tester), isFalse);

    await openDetail(tester, '测试基金A · 买入');
    await tester.scrollUntilVisible(
      find.text('撤销交易'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('撤销交易'));
    await tester.pumpAndSettle();
    expect(find.text('交易记录'), findsOneWidget);
    expect(cleanupEnabled(tester), isTrue);
  });

  testWidgets('cleanup counts every cancelled record on the unfiltered page', (
    tester,
  ) async {
    final repository = HistoryRepository([
      record(id: 'own-pending', date: '2026-09-24', status: 'pending'),
      record(id: 'own-cancelled', date: '2026-09-23', status: 'cancelled'),
      record(
        id: 'other-cancelled',
        date: '2026-09-22',
        status: 'cancelled',
        type: 'sell',
        fundCode: '000002',
        fundName: '其他基金',
      ),
    ]);
    await tester.pumpWidget(page(repository));
    await tester.pumpAndSettle();
    await tester.tap(cleanupButton());
    await tester.pumpAndSettle();
    expect(find.text('确定删除全部 2 条已取消交易吗？删除后无法恢复。'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(repository.clearCalls, 0);
    expect(repository.records, hasLength(3));

    await tester.tap(cleanupButton());
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除全部'));
    await expectSnack(tester, '已清理 2 条已取消交易');
    expect(repository.clearCalls, 1);
    expect(repository.records.map((item) => item['id']), ['own-pending']);
    expect(find.text('已取消'), findsNothing);
    expect(find.text('待确认'), findsOneWidget);
  });

  testWidgets('cleanup only removes cancelled records of the filtered fund', (
    tester,
  ) async {
    final repository = HistoryRepository([
      record(
        id: 'own-cancelled',
        date: '2026-09-23',
        status: 'cancelled',
        fundName: '自有基金',
      ),
      record(
        id: 'other-cancelled',
        date: '2026-09-22',
        status: 'cancelled',
        type: 'sell',
        fundCode: '000002',
        fundName: '其他基金',
      ),
    ]);
    await tester.pumpWidget(page(repository, fundCode: '000002'));
    await tester.pumpAndSettle();
    expect(find.text('其他基金 · 卖出'), findsOneWidget);
    expect(find.text('自有基金 · 买入'), findsNothing);
    await tester.tap(cleanupButton());
    await tester.pumpAndSettle();
    expect(find.text('确定删除全部 1 条已取消交易吗？删除后无法恢复。'), findsOneWidget);
    await tester.tap(find.text('删除全部'));
    await expectSnack(tester, '已清理 1 条已取消交易');
    expect(repository.records.map((item) => item['id']), ['own-cancelled']);
    expect(find.text('暂无交易记录'), findsOneWidget);
  });

  testWidgets('long press only offers deletion for cancelled records', (
    tester,
  ) async {
    final repository = HistoryRepository([
      record(id: 'confirmed', date: '2026-09-24'),
      record(
        id: 'pending',
        date: '2026-09-23',
        status: 'pending',
        type: 'sell',
      ),
      record(
        id: 'cancelled',
        date: '2026-09-22',
        status: 'cancelled',
        fundName: '已取消基金',
      ),
    ]);
    await tester.pumpWidget(page(repository));
    await tester.pumpAndSettle();

    await openDeleteMenu(tester, '已取消基金 · 买入');
    expect(find.text('删除交易'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(repository.deleteCalls, 0);
    expect(find.text('已取消'), findsOneWidget);

    // Confirmed and pending records keep the original tap-to-detail behaviour.
    await openDetail(tester, '测试基金A · 买入');
    expect(find.text('交易详情'), findsOneWidget);
    expect(find.text('删除交易'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.longPress(find.text('测试基金A · 卖出'));
    await tester.pumpAndSettle();
    expect(find.text('交易详情'), findsOneWidget);
    expect(find.text('删除交易'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(repository.deleteCalls, 0);
    expect(repository.records, hasLength(3));
  });

  testWidgets('keeps the record when the delete confirmation is dismissed', (
    tester,
  ) async {
    final repository = HistoryRepository([
      record(
        id: 'cancelled',
        date: '2026-09-22',
        status: 'cancelled',
        type: 'sell',
      ),
    ]);
    await tester.pumpWidget(page(repository));
    await tester.pumpAndSettle();
    await openDeleteMenu(tester, '测试基金A · 卖出');
    await tester.tap(find.text('删除交易'));
    await tester.pumpAndSettle();
    expect(find.text('删除交易记录？'), findsOneWidget);
    expect(find.text('这条已取消交易将被永久删除，无法恢复。'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(repository.deleteCalls, 0);
    expect(find.text('已取消'), findsOneWidget);
  });

  testWidgets('deletes a cancelled record and keeps the other records', (
    tester,
  ) async {
    final repository = HistoryRepository([
      record(id: 'confirmed', date: '2026-09-24'),
      record(
        id: 'cancelled',
        date: '2026-09-22',
        status: 'cancelled',
        type: 'sell',
      ),
    ]);
    await tester.pumpWidget(page(repository));
    await tester.pumpAndSettle();
    await openDeleteMenu(tester, '测试基金A · 卖出');
    await tester.tap(find.text('删除交易'));
    await tester.pumpAndSettle();
    await confirmDeleteDialog(tester, '删除交易记录？');

    expect(repository.lastDeletedId, 'cancelled');
    await expectSnack(tester, '交易记录已删除');
    expect(find.text('已取消'), findsNothing);
    expect(find.text('已确认'), findsOneWidget);
  });

  testWidgets('shows the empty state after the last record is deleted', (
    tester,
  ) async {
    final repository = HistoryRepository([
      record(
        id: 'cancelled',
        date: '2026-09-22',
        status: 'cancelled',
        type: 'sell',
      ),
    ]);
    await tester.pumpWidget(page(repository));
    await tester.pumpAndSettle();
    await openDeleteMenu(tester, '测试基金A · 卖出');
    await tester.tap(find.text('删除交易'));
    await tester.pumpAndSettle();
    await confirmDeleteDialog(tester, '删除交易记录？');
    expect(find.text('暂无交易记录'), findsOneWidget);
  });

  testWidgets('keeps the list and reports an error when deletion fails', (
    tester,
  ) async {
    final repository = HistoryRepository([
      record(id: 'confirmed', date: '2026-09-24'),
      record(
        id: 'cancelled',
        date: '2026-09-22',
        status: 'cancelled',
        type: 'sell',
      ),
    ], failDeletes: true);
    await tester.pumpWidget(page(repository));
    await tester.pumpAndSettle();
    await openDeleteMenu(tester, '测试基金A · 卖出');
    await tester.tap(find.text('删除交易'));
    await tester.pumpAndSettle();
    await confirmDeleteDialog(tester, '删除交易记录？');
    await expectSnack(tester, '删除失败：记录不存在');
    expect(find.text('已取消'), findsOneWidget);
    expect(find.text('已确认'), findsOneWidget);
  });

  testWidgets('detail page deletes a cancelled record and reloads the list', (
    tester,
  ) async {
    final repository = HistoryRepository([
      record(id: 'confirmed', date: '2026-09-24'),
      record(
        id: 'cancelled',
        date: '2026-09-22',
        status: 'cancelled',
        type: 'sell',
      ),
    ]);
    await tester.pumpWidget(page(repository));
    await tester.pumpAndSettle();
    await openDetail(tester, '测试基金A · 卖出');
    await tester.scrollUntilVisible(
      find.text('取消时间'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('撤销交易'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('删除交易'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('删除交易'));
    await tester.pumpAndSettle();
    await confirmDeleteDialog(tester, '删除交易记录？');
    expect(repository.lastDeletedId, 'cancelled');
    await expectSnack(tester, '交易记录已删除');
    // Wait for the detail route to finish popping before inspecting the list.
    await tester.pumpAndSettle();
    expect(find.text('交易记录'), findsOneWidget);
    expect(find.text('交易详情'), findsNothing);
    expect(find.text('2026-09-24 · 净值日期 2026-09-24'), findsOneWidget);
    expect(find.text('2026-09-22 · 净值日期 2026-09-24'), findsNothing);
    expect(find.text('已取消'), findsNothing);
    expect(find.text('已确认'), findsOneWidget);
  });
}
