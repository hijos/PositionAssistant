import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:position_assistant/data/fund_catalog_repository.dart';
import 'package:position_assistant/data/sqlite_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test('searches Chinese fund names after refreshing the local catalog', () async {
    final repository = await SqliteRepository.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final api = LocalFundCatalogRepository(
      () async => repository,
      client: MockClient((_) async => http.Response.bytes(
        utf8.encode('var r = [["012752","JXNSDK100ZSQDIICRMB","建信纳斯达克100指数(QDII)C人民币","指数型-海外股票"]];'),
        200,
      )),
    );
    final count = await api.refresh(repository);
    expect(count, 1);
    expect(await repository.list(fundCatalogCollection), hasLength(1));
    final results = await api.search('纳斯达克');
    expect(results.single['code'], '012752');
    await repository.close();
    api.close();
  });
}