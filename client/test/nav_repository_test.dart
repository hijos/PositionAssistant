import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:position_assistant/data/nav_repository.dart';
import 'package:position_assistant/data/sqlite_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

http.Client _clientWithRows(Map<String, List<Map<String, dynamic>>> rows) {
  return MockClient((request) async {
    final code = request.url.queryParameters['fundCode'] ?? '';
    final list = rows[code] ?? const [];
    return http.Response(
      jsonEncode({
        'Data': {'LSJZList': list},
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

void main() {
  late Directory directory;
  late SqliteRepository repository;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('position_nav_');
    repository = await SqliteRepository.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/test.db',
    );
  });
  tearDown(() async {
    await repository.close();
    await directory.delete(recursive: true);
  });

  test('refreshLatest pulls the newest NAV and updates stale fund values',
      () async {
    await repository.put('funds', '539001', {
      'code': '539001',
      'name': '建信纳斯达克100指数(QDII)A人民币',
      'type': 'QDII',
      'nav': 3.4181,
      'navDate': '2026-08-25',
    });
    await repository.put('funds', '000001', {
      'code': '000001',
      'name': '测试基金A',
      'type': '混合型',
      'nav': 1.5,
      'navDate': '2026-09-28',
    });
    final nav = LocalNavRepository(
      () async => repository,
      client: _clientWithRows({
        '539001': [
          {'FSRQ': '2026-09-28', 'DWJZ': '3.5'},
        ],
        '000001': [
          {'FSRQ': '2026-09-28', 'DWJZ': '1.5'},
        ],
      }),
    );

    await nav.refreshLatest();

    final updated = await repository.get('funds', '539001');
    expect(updated?['nav'], 3.5);
    expect(updated?['navDate'], '2026-09-28');
    expect(updated?['navSource'], 'eastmoney-local-nav-v1');
    final snapshot = await repository.get(
      'navSnapshots',
      '539001:2026-09-28:remote',
    );
    expect(snapshot?['nav'], 3.5);
    // A fund that is already current stays untouched but gains no regression.
    final current = await repository.get('funds', '000001');
    expect(current?['nav'], 1.5);
    expect(current?['navDate'], '2026-09-28');
  });

  test('refreshLatest keeps previous values when the upstream fetch fails',
      () async {
    await repository.put('funds', '539001', {
      'code': '539001',
      'name': '建信纳斯达克100指数(QDII)A人民币',
      'type': 'QDII',
      'nav': 3.4181,
      'navDate': '2026-08-25',
    });
    final nav = LocalNavRepository(
      () async => repository,
      client: MockClient((request) async => http.Response('error', 502)),
    );

    await nav.refreshLatest();

    final fund = await repository.get('funds', '539001');
    expect(fund?['nav'], 3.4181);
    expect(fund?['navDate'], '2026-08-25');
    expect(await repository.list('navSnapshots'), isEmpty);
  });

  test('refreshLatest never moves a fund back to an older NAV', () async {
    await repository.put('funds', '539001', {
      'code': '539001',
      'name': '建信纳斯达克100指数(QDII)A人民币',
      'type': 'QDII',
      'nav': 3.5,
      'navDate': '2026-09-28',
    });
    final nav = LocalNavRepository(
      () async => repository,
      client: _clientWithRows({
        '539001': [
          {'FSRQ': '2026-08-25', 'DWJZ': '3.4181'},
        ],
      }),
    );

    await nav.refreshLatest();

    final fund = await repository.get('funds', '539001');
    expect(fund?['nav'], 3.5);
    expect(fund?['navDate'], '2026-09-28');
  });
}
