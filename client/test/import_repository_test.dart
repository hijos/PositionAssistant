import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:position_assistant/data/import_repository.dart';
import 'package:position_assistant/data/repository.dart';
import 'package:position_assistant/data/sqlite_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory directory;
  late SqliteRepository repository;
  late String path;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('position_import_');
    path = '${directory.path}/test.db';
    repository = await SqliteRepository.open(
      factory: databaseFactoryFfi,
      path: path,
    );
  });
  tearDown(() async {
    await repository.close();
    await directory.delete(recursive: true);
  });

  test(
    'valid package fully replaces all local collections and survives reopen',
    () async {
      await _seed(repository, 'old');
      final package = validateLocalImport(_package('new'));
      final summary = await importLocalPackage(repository, package);

      expect(summary.total, 5);
      expect(await repository.list('funds'), [
        {'code': '000002', 'name': '新基金', 'type': '混合型'},
      ]);
      expect((await repository.list('transactions')).single['id'], 'tx-new');
      expect((await repository.list('plans')).single['id'], 'plan-new');
      expect((await repository.list('planEntries')).single['id'], 'entry-new');
      expect(
        (await repository.list('quotaOverrides')).single['code'],
        '000002',
      );

      await repository.close();
      repository = await SqliteRepository.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      expect((await repository.list('funds')).single['code'], '000002');
      expect((await repository.list('transactions')).single['id'], 'tx-new');
    },
  );

  test('invalid package is rejected before changing local data', () async {
    await _seed(repository, 'old');
    final invalid = _package('new');
    (invalid['data'] as Map<String, dynamic>)['funds'] = [
      {'code': '000002', 'name': '新基金', 'type': '混合型'},
      {'code': '000002', 'name': '重复基金', 'type': '混合型'},
    ];
    expect(() => validateLocalImport(invalid), throwsA(isA<FormatException>()));
    expect((await repository.list('funds')).single['code'], '000001');
    expect((await repository.list('transactions')).single['id'], 'tx-old');
  });

  test('failure during replacement rolls back every collection', () async {
    await _seed(repository, 'old');
    final package = validateLocalImport(_package('new'));
    final failing = _FailingRepository(repository);
    await expectLater(importLocalPackage(failing, package), throwsStateError);
    expect((await repository.list('funds')).single['code'], '000001');
    expect((await repository.list('transactions')).single['id'], 'tx-old');
    expect((await repository.list('plans')).single['id'], 'plan-old');
    expect((await repository.list('planEntries')).single['id'], 'entry-old');
    expect((await repository.list('quotaOverrides')).single['code'], '000001');
  });
}

Map<String, dynamic> _package(String suffix) => {
  'format': importFormat,
  'version': importVersion,
  'exportedAt': '2026-09-26T00:00:00Z',
  'data': {
    'funds': [
      {
        'code': suffix == 'new' ? '000002' : '000001',
        'name': suffix == 'new' ? '新基金' : '旧基金',
        'type': '混合型',
      },
    ],
    'transactions': [
      {'id': 'tx-$suffix', 'fundCode': suffix == 'new' ? '000002' : '000001'},
    ],
    'plans': [
      {'id': 'plan-$suffix', 'fundCode': suffix == 'new' ? '000002' : '000001'},
    ],
    'planEntries': [
      {'id': 'entry-$suffix', 'planId': 'plan-$suffix'},
    ],
    'quotaOverrides': [
      {'code': suffix == 'new' ? '000002' : '000001', 'limit': 100},
    ],
  },
};

Future<void> _seed(SqliteRepository repository, String suffix) async {
  final package = validateLocalImport(_package(suffix));
  for (final collection in importCollections) {
    final record = package.data[collection]!.single;
    final id = collection == 'funds' || collection == 'quotaOverrides'
        ? record['code'] as String
        : record['id'] as String;
    await repository.put(collection, id, record);
  }
}

class _FailingRepository implements Repository {
  _FailingRepository(this.delegate);
  final SqliteRepository delegate;

  @override
  Future<Map<String, dynamic>?> get(String collection, String id) =>
      delegate.get(collection, id);

  @override
  Future<List<Map<String, dynamic>>> list(String collection) =>
      delegate.list(collection);

  @override
  Future<void> put(String collection, String id, Map<String, dynamic> value) =>
      delegate.put(collection, id, value);

  @override
  Future<void> delete(String collection, String id) =>
      delegate.delete(collection, id);

  @override
  Future<T> transaction<T>(Future<T> Function(RepositorySession) action) =>
      delegate.transaction((session) => action(_FailingSession(session)));

  @override
  Future<void> close() => delegate.close();
}

class _FailingSession implements RepositorySession {
  _FailingSession(this.delegate);
  final RepositorySession delegate;

  @override
  Future<Map<String, dynamic>?> get(String collection, String id) =>
      delegate.get(collection, id);

  @override
  Future<List<Map<String, dynamic>>> list(String collection) =>
      delegate.list(collection);

  @override
  Future<void> put(String collection, String id, Map<String, dynamic> value) {
    if (collection == 'plans') throw StateError('injected import failure');
    return delegate.put(collection, id, value);
  }

  @override
  Future<void> delete(String collection, String id) =>
      delegate.delete(collection, id);
}
