import 'dart:io';

import 'package:position_assistant/data/fund_repository.dart';
import 'package:position_assistant/data/holding_repository.dart';
import 'package:position_assistant/data/transaction_repository.dart';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:position_assistant/data/nav_repository.dart';
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
}
