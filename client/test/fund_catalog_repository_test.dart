import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:position_assistant/data/fund_catalog_repository.dart';
import 'package:position_assistant/data/sqlite_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test('keeps ETF launch联接 share classes searchable', () {
    expect(LocalFundCatalogRepository.supported({
      'code': '015299',
      'name': '华夏纳斯达克100ETF发起式联接(QDII)A',
      'type': '指数型-海外股票',
    }), isTrue);
    expect(LocalFundCatalogRepository.supported({
      'code': '015300',
      'name': '华夏纳斯达克100ETF发起式联接(QDII)C',
      'type': '指数型-海外股票',
    }), isTrue);
  });
  test('searches Chinese fund names after refreshing the local catalog', () async {
    final repository = await SqliteRepository.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final api = LocalFundCatalogRepository(
      () async => repository,
      client: MockClient((_) async => http.Response.bytes(
        utf8.encode('var r = [["012752","JXNSDK100ZSQDIICRMB","建信纳斯达克100指数(QDII)C人民币","指数型-海外股票"],["015299","HXNSDK100ETFQSLJQDIIA","华夏纳斯达克100ETF发起式联接(QDII)A","指数型-海外股票"],["015300","HXNSDK100ETFQSLJQDIIC","华夏纳斯达克100ETF发起式联接(QDII)C","指数型-海外股票"]];'),
        200,
      )),
    );
    final count = await api.refresh(repository);
    expect(count, 3);
    expect(await repository.list(fundCatalogCollection), hasLength(3));
    final results = await api.search('华夏纳斯达克');
    expect(results.map((item) => item['code']), containsAll(<String>['015299', '015300']));
    expect((await api.search('015299')).single['name'], '华夏纳斯达克100ETF发起式联接(QDII)A');
    await repository.close();
    api.close();
  });
}
