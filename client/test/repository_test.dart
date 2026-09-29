import 'dart:io';

import 'package:position_assistant/data/fund_repository.dart';
import 'package:position_assistant/data/holding_repository.dart';
import 'package:position_assistant/data/transaction_repository.dart';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:position_assistant/data/nav_repository.dart';
import 'package:position_assistant/data/repository.dart';
import 'package:position_assistant/data/sqlite_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory directory;
  late SqliteRepository repository;
  late String path;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('position_repository_');
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

  test('fund additions are atomic, idempotent and survive reopen', () async {
    final funds = LocalFundRepository(() async => repository);
    final record = {'code': '000001', 'name': '测试基金A', 'type': '混合型'};
    await Future.wait(List.generate(8, (_) => funds.add(record)));
    await funds.add({...record, 'name': '不得覆盖'});
    expect(await funds.list(), [record]);
    await expectLater(
      funds.add({...record, 'code': 'bad'}),
      throwsFormatException,
    );
    await repository.close();
    repository = await SqliteRepository.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    expect(await funds.list(), [record]);
    expect(await repository.list('transactions'), isEmpty);
  });

  test('local holdings calculate formal value, profit and rate from confirmed ledger', () async {
    await repository.put('funds', '000001', {
      'code': '000001',
      'name': '测试基金A',
      'type': '混合型',
      'nav': 3.456,
      'navDate': '2026-09-24',
    });
    await repository.put('transactions', 'buy', {
      'fundCode': '000001',
      'fundName': '测试基金A',
      'type': 'buy',
      'amount': 20,
      'shares': 10,
      'fee': 0,
      'date': '2026-09-23',
      'cutoff': 'before',
      'status': 'confirmed',
    });
    await repository.put('transactions', 'sell', {
      'fundCode': '000001',
      'fundName': '测试基金A',
      'type': 'sell',
      'amount': 6.1,
      'shares': 2,
      'fee': 0.1,
      'date': '2026-09-24',
      'cutoff': 'before',
      'status': 'confirmed',
    });
    final item = (await LocalHoldingRepository(
      () async => repository,
    ).list()).single;
    expect(item['shares'], 8);
    expect(item['cost'], 16);
    expect(item['marketValue'], 27.65);
    expect(item['profit'], 11.65);
    expect(item['profitRate'], closeTo(11.65 / 16, 1e-12));
  });

  test(
    'remote holdings derive the estimated market value when the API omits it',
    () async {
      final holdings = RemoteHoldingRepository(
        token: 'token',
        client: MockClient(
          (request) async => http.Response.bytes(
            utf8.encode(
              jsonEncode([
                {
                  'fundCode': '539001',
                  'fundName': '建信纳斯达克100指数（QDII）A人民币',
                  'shares': 310.96,
                  'cost': 1050.0,
                  'marketValue': 1093.74,
                  'profit': 43.74,
                  'profitRate': 0.041657,
                  'estimatedProfit': 70.5,
                },
                {
                  'fundCode': '000002',
                  'shares': 10,
                  'cost': 100.0,
                  'marketValue': null,
                  'profit': null,
                  'estimatedProfit': null,
                },
              ]),
            ),
            200,
          ),
        ),
      );
      final items = await holdings.list();
      // estimatedMarketValue = estimatedProfit + cost, while a missing
      // estimate keeps producing `—` instead of a fabricated figure.
      expect(items[0]['estimatedMarketValue'], 1120.5);
      expect(items[0]['estimatedProfitRate'], closeTo(70.5 / 1050, 1e-12));
      expect(items[1]['estimatedMarketValue'], isNull);
      expect(items[1]['estimatedProfitRate'], isNull);
    },
  );

  test(
    'local buy transactions validate and persist as pending records',
    () async {
      final transactions = LocalTransactionRepository(
        () async => repository,
        // Offline NAV stub: keeps the created transaction pending instead of
        // hitting the real eastmoney API during tests.
        nav: LocalNavRepository(
          () async => repository,
          client: MockClient((request) async => http.Response('', 500)),
        ),
      );
      final saved = await transactions.create({
        'fundCode': '000001',
        'fundName': '测试基金A',
        'fundType': '混合型',
        'entryMode': 'amount',
        'amount': '100.00',
        'shares': 0,
        'feeMode': 'fixed',
        'feeRate': 0,
        'fixedFee': '1.00',
        'date': '2026-09-24',
        'cutoff': 'after',
      });
      expect(saved['status'], 'pending');
      expect(saved['fixedFee'], 1);
      expect((await transactions.list()).single['fundCode'], '000001');
      await expectLater(
        transactions.create({...saved, 'amount': 0}),
        throwsFormatException,
      );
    },
  );

  test('persists JSON across reopen and isolates collections', () async {
    final data = {
      'name': '基金',
      'amount': '123.4500',
      'nested': {'active': true},
    };
    await repository.put('funds', "id'1", data);
    await repository.put('plans', "id'1", {'name': 'plan'});
    await repository.close();
    repository = await SqliteRepository.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    expect(await repository.get('funds', "id'1"), data);
    expect(await repository.list('plans'), [
      {'name': 'plan'},
    ]);
    await repository.put('funds', "id'1", {'name': 'updated'});
    expect(await repository.list('funds'), [
      {'name': 'updated'},
    ]);
    await repository.delete('funds', "id'1");
    expect(await repository.get('funds', "id'1"), isNull);
    expect(await repository.list('plans'), hasLength(1));
  });

  test(
    'transaction commits together and rolls back writes and deletes',
    () async {
      await repository.transaction((session) async {
        await session.put('funds', '1', {'name': 'original'});
        await session.put('plans', '1', {'name': 'original'});
      });
      await expectLater(
        repository.transaction((session) async {
          await session.delete('funds', '1');
          await session.put('plans', '1', {'name': 'changed'});
          await session.put('funds', '2', {'name': 'new'});
          throw StateError('abort');
        }),
        throwsStateError,
      );
      expect(await repository.list('funds'), [
        {'name': 'original'},
      ]);
      expect(await repository.list('plans'), [
        {'name': 'original'},
      ]);
    },
  );

  test(
    'rejects invalid keys and non JSON values without changing data',
    () async {
      await expectLater(repository.put('', '1', {}), throwsArgumentError);
      await expectLater(repository.put('funds', ' ', {}), throwsArgumentError);
      await expectLater(
        repository.put('funds', '1', {'bad': Object()}),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );
      expect(await repository.list('funds'), isEmpty);
    },
  );

  test(
    'local confirmed history rejects a sell larger than available shares',
    () async {
      await repository.put('transactions', 'confirmed-buy', {
        'fundCode': '000001',
        'type': 'buy',
        'entryMode': 'shares',
        'shares': 10,
        'amount': 20,
        'date': '2026-09-23',
        'cutoff': 'before',
        'status': 'confirmed',
      });
      final transactions = LocalTransactionRepository(() async => repository);
      await expectLater(
        transactions.create({
          'fundCode': '000001',
          'fundName': '测试基金A',
          'fundType': '混合型',
          'type': 'sell',
          'entryMode': 'shares',
          'amount': 0,
          'shares': 10.01,
          'feeMode': 'fixed',
          'feeRate': 0,
          'fixedFee': 0,
          'date': '2026-09-24',
          'cutoff': 'before',
        }),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test(
    'local cancellation preserves history and recomputes the ledger',
    () async {
      await repository.put('transactions', 'buy-1', {
        'id': 'buy-1',
        'fundCode': '000001',
        'type': 'buy',
        'entryMode': 'shares',
        'shares': 10,
        'amount': 20,
        'date': '2026-09-23',
        'cutoff': 'before',
        'status': 'confirmed',
      });
      await repository.put('transactions', 'sell-1', {
        'id': 'sell-1',
        'fundCode': '000001',
        'type': 'sell',
        'entryMode': 'shares',
        'shares': 4,
        'amount': 8,
        'date': '2026-09-24',
        'cutoff': 'before',
        'status': 'confirmed',
      });
      final transactions = LocalTransactionRepository(() async => repository);
      await expectLater(transactions.cancel('buy-1'), throwsFormatException);
      expect(
        (await transactions.list()).firstWhere(
          (x) => x['id'] == 'buy-1',
        )['status'],
        'confirmed',
      );
      final cancelledSell = await transactions.cancel('sell-1');
      expect(cancelledSell['status'], 'cancelled');
      expect(cancelledSell['cancelledAt'], isNotNull);
      final cancelledBuy = await transactions.cancel('buy-1');
      expect(cancelledBuy['status'], 'cancelled');
      expect(
        (await transactions.cancel('buy-1'))['cancelledAt'],
        cancelledBuy['cancelledAt'],
      );
      expect((await transactions.list()).map((x) => x['status']), [
        'cancelled',
        'cancelled',
      ]);
    },
  );

  test('local permanent delete removes only cancelled records', () async {
    for (final entry in {
      'confirmed': 'confirmed',
      'pending': 'pending',
      'cancelled': 'cancelled',
    }.entries) {
      await repository.put('transactions', entry.key, {
        'id': entry.key,
        'fundCode': '000001',
        'type': 'buy',
        'entryMode': 'shares',
        'shares': 10,
        'amount': 20,
        'date': '2026-09-24',
        'cutoff': 'before',
        'status': entry.value,
      });
    }
    final transactions = LocalTransactionRepository(() async => repository);
    await expectLater(
      transactions.deleteCancelled('confirmed'),
      throwsFormatException,
    );
    await expectLater(
      transactions.deleteCancelled('pending'),
      throwsFormatException,
    );
    await expectLater(
      transactions.deleteCancelled('missing'),
      throwsFormatException,
    );
    await expectLater(
      transactions.deleteCancelled('  '),
      throwsFormatException,
    );
    expect((await transactions.list()).map((x) => x['id']), [
      'cancelled',
      'confirmed',
      'pending',
    ]);

    await transactions.deleteCancelled('cancelled');
    expect((await transactions.list()).map((x) => x['id']), [
      'confirmed',
      'pending',
    ]);
    // The deleted record stays gone after reopening the database file.
    await repository.close();
    repository = await SqliteRepository.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    expect(
      (await LocalTransactionRepository(
        () async => repository,
      ).list()).map((x) => x['id']),
      ['confirmed', 'pending'],
    );
  });

  test('local clearCancelled removes every cancelled record only', () async {
    for (final entry in {
      'cancelled-a': 'cancelled',
      'confirmed': 'confirmed',
      'cancelled-b': 'cancelled',
      'pending': 'pending',
    }.entries) {
      await repository.put('transactions', entry.key, {
        'id': entry.key,
        'fundCode': '000001',
        'status': entry.value,
      });
    }
    final transactions = LocalTransactionRepository(() async => repository);
    expect(await transactions.clearCancelled(), 2);
    expect((await transactions.list()).map((x) => x['id']), [
      'confirmed',
      'pending',
    ]);
    // Idempotent: a second pass has nothing left to delete.
    expect(await transactions.clearCancelled(), 0);
    expect((await transactions.list()), hasLength(2));
  });

  test('failed local clear rolls back and keeps the record', () async {
    await repository.put('transactions', 'cancelled', {
      'id': 'cancelled',
      'fundCode': '000001',
      'status': 'cancelled',
    });
    final transactions = LocalTransactionRepository(
      () async => _FailingDeleteRepository(repository, 'cancelled'),
    );
    await expectLater(
      transactions.clearCancelled(),
      throwsA(isA<StateError>()),
    );
    expect(
      (await repository.list('transactions')).single['status'],
      'cancelled',
    );
  });
}

/// Fails the delete of [failId] so the transaction rollback can be asserted.
class _FailingDeleteRepository implements Repository {
  _FailingDeleteRepository(this._delegate, this.failId);

  final Repository _delegate;
  final String failId;

  @override
  Future<T> transaction<T>(Future<T> Function(RepositorySession) action) =>
      _delegate.transaction(
        (session) => action(_FailingSession(session, failId)),
      );

  @override
  Future<Map<String, dynamic>?> get(String collection, String id) =>
      _delegate.get(collection, id);

  @override
  Future<List<Map<String, dynamic>>> list(String collection) =>
      _delegate.list(collection);

  @override
  Future<void> put(String collection, String id, Map<String, dynamic> value) =>
      _delegate.put(collection, id, value);

  @override
  Future<void> delete(String collection, String id) =>
      _delegate.delete(collection, id);

  @override
  Future<void> close() => _delegate.close();
}

class _FailingSession implements RepositorySession {
  _FailingSession(this._delegate, this.failId);

  final RepositorySession _delegate;
  final String failId;

  @override
  Future<Map<String, dynamic>?> get(String collection, String id) =>
      _delegate.get(collection, id);

  @override
  Future<List<Map<String, dynamic>>> list(String collection) =>
      _delegate.list(collection);

  @override
  Future<void> put(String collection, String id, Map<String, dynamic> value) =>
      _delegate.put(collection, id, value);

  @override
  Future<void> delete(String collection, String id) async {
    if (id == failId) throw StateError('delete failed');
    await _delegate.delete(collection, id);
  }
}
