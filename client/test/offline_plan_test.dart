import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:position_assistant/data/offline_repository.dart';
import 'package:position_assistant/data/repository.dart';
import 'package:position_assistant/data/sqlite_repository.dart';
import 'package:position_assistant/offline_pages.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory directory;
  late SqliteRepository repository;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('position_plan_page_');
    repository = await SqliteRepository.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/plans.db',
    );
  });
  tearDown(() async {
    await repository.close();
    await directory.delete(recursive: true);
  });

  testWidgets('long press offers deletion and requires confirmation', (
    tester,
  ) async {
    final repository = _MemoryRepository();
    final plans = LocalPlanRepository(() async => repository);
    final plan = await plans.create(
      fundCode: '000001',
      fundName: '本地基金',
      mode: 'amount',
      value: 100,
      cycle: 'daily',
      startDate: '2099-01-01',
      executionDay: 1,
    );
    await plans.generateEntry(plan['id'] as String, '2099-01-01');
    await tester.pumpWidget(
      MaterialApp(home: LocalPlansPage(open: () async => repository)),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.longPress(find.text('本地基金 · 000001'));
    await tester.pumpAndSettle();
    expect(find.text('删除定投计划'), findsOneWidget);
    await tester.tap(find.text('删除定投计划'));
    await tester.pumpAndSettle();
    expect(find.text('删除定投计划？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await plans.list(), hasLength(1));

    await tester.longPress(find.text('本地基金 · 000001'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除定投计划'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('暂无定投计划'), findsOneWidget);
    expect(await plans.list(), isEmpty);
    expect(await repository.list('planEntries'), isEmpty);
  });

  testWidgets('new plan dialog is wider and exposes daily scheduling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: LocalPlansPage(open: () async => repository)),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();

    expect(find.text('新建定投计划'), findsOneWidget);
    expect(tester.getSize(find.byType(AlertDialog)).width, greaterThan(560));
    expect(find.text('交易方向'), findsOneWidget);
    expect(find.text('手续费'), findsOneWidget);
    expect(find.text('来源'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('每月'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('每月'));
    await tester.pump();
    expect(find.text('每天'), findsOneWidget);
  });

  testWidgets('entry page keeps supplement and deletes pending records', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final memory = _MemoryRepository();
    final plans = LocalPlanRepository(() async => memory);
    final created = await plans.create(
      fundCode: '000001',
      fundName: '本地基金',
      mode: 'amount',
      value: 100,
      cycle: 'daily',
      startDate: '2099-01-01',
      executionDay: 1,
    );
    final paused = await plans.setEnabled(created['id'] as String, false);
    await plans.generateEntry(
      created['id'] as String,
      '2099-01-01',
      supplement: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LocalPlanEntriesPage(repository: plans, plan: paused),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('生成一期'), findsNothing);
    expect(find.text('补录一期'), findsNothing);
    expect(find.text('补录'), findsOneWidget);
    expect(find.text('跳过'), findsNothing);
    expect(find.text('删除'), findsOneWidget);
    final supplementButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '补录'),
    );
    expect(supplementButton.onPressed, isNotNull);
    expect(tester.getSize(find.byType(Card)).width, greaterThan(700));

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除本期记录？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(find.text('2099-01-01 · 买入'), findsNothing);
    expect(await plans.entries(created['id'] as String), isEmpty);
  });
}

class _MemoryRepository implements Repository {
  final records = <String, Map<String, Map<String, dynamic>>>{};
  @override
  Future<Map<String, dynamic>?> get(String collection, String id) async =>
      records[collection]?[id];
  @override
  Future<List<Map<String, dynamic>>> list(String collection) async =>
      records[collection]?.values.toList() ?? [];
  @override
  Future<void> put(
    String collection,
    String id,
    Map<String, dynamic> value,
  ) async {
    (records[collection] ??= {})[id] = value;
  }

  @override
  Future<void> delete(String collection, String id) async {
    records[collection]?.remove(id);
  }

  @override
  Future<T> transaction<T>(Future<T> Function(RepositorySession) action) =>
      action(this);
  @override
  Future<void> close() async {}
}
