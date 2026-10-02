import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:position_assistant/data/quota_repository.dart';
import 'package:position_assistant/data/repository.dart';

class _MemoryRepository implements Repository {
  final Map<String, Map<String, Map<String, dynamic>>> _collections = {};

  Map<String, Map<String, dynamic>> _collection(String name) =>
      _collections.putIfAbsent(name, () => {});

  @override
  Future<Map<String, dynamic>?> get(String collection, String id) async {
    final value = _collection(collection)[id];
    return value == null ? null : Map<String, dynamic>.from(value);
  }

  @override
  Future<List<Map<String, dynamic>>> list(String collection) async =>
      _collection(collection).values.map(Map<String, dynamic>.from).toList();

  @override
  Future<void> put(String collection, String id, Map<String, dynamic> value) async {
    _collection(collection)[id] = Map<String, dynamic>.from(value);
  }

  @override
  Future<void> delete(String collection, String id) async {
    _collection(collection).remove(id);
  }

  @override
  Future<T> transaction<T>(Future<T> Function(RepositorySession session) action) =>
      action(this);

  @override
  Future<void> close() async {}
}

void main() {
  test('classifies supported RMB Nasdaq and S&P QDII funds', () {
    expect(quotaCategory('建信纳斯达克100指数(QDII)A人民币'), '纳斯达克100');
    expect(quotaCategory('华夏标普500ETF联接(QDII)'), '标普500');
    expect(quotaCandidate({'name': '建信纳斯达克100指数(QDII)A人民币', 'type': 'QDII'}), isTrue);
    expect(quotaCandidate({'name': '纳斯达克100指数(QDII)美元', 'type': 'QDII'}), isFalse);
    expect(quotaCandidate({'name': '标普500 ETF', 'type': '指数型'}), isFalse);
  });

  test('extracts share class letters across catalog naming patterns', () {
    expect(quotaShareClass('招商纳斯达克100ETF发起式联接(QDII)A'), 'A');
    expect(quotaShareClass('招商纳斯达克100ETF发起式联接(QDII)C'), 'C');
    expect(quotaShareClass('华泰柏瑞纳斯达克100ETF发起式联接(QDII)I'), 'I');
    expect(quotaShareClass('大成标普500等权重指数(QDII)C人民币'), 'C');
    expect(quotaShareClass('摩根标普500指数(QDII)人民币A'), 'A');
    expect(quotaShareClass('华夏标普500ETF发起式联接(QDII)A(人民币)'), 'A');
    expect(quotaShareClass('易方达纳斯达克100ETF联接(QDII-LOF)C(人民币)'), 'C');
    expect(quotaShareClass('广发纳指100ETF联接(QDII)人民币F'), 'F');
    expect(quotaShareClass('国泰纳斯达克100指数'), isNull);
    expect(quotaShareClass('摩根标普500指数(QDII)美钞'), isNull);
    expect(quotaShareClass('摩根标普500指数(QDII)美汇'), isNull);
    // Letters inside Latin abbreviations are not share classes.
    expect(quotaShareClass('华夏标普500ETF联接(QDII)'), isNull);
    expect(quotaShareClass('某纳斯达克100ETF'), isNull);
  });

  test('groups share classes of one fund under the same family name', () {
    expect(quotaFamilyName('招商纳斯达克100ETF发起式联接(QDII)A'), quotaFamilyName('招商纳斯达克100ETF发起式联接(QDII)C'));
    expect(quotaFamilyName('华夏标普500ETF发起式联接(QDII)A(人民币)'), quotaFamilyName('华夏标普500ETF发起式联接(QDII)C'));
    expect(quotaFamilyName('摩根标普500指数(QDII)人民币A'), quotaFamilyName('摩根标普500指数(QDII)人民币C'));
    expect(quotaFamilyName('摩根标普500指数(QDII)人民币A'), quotaFamilyName('摩根标普500指数(QDII)美钞'));
    expect(quotaFamilyName('易方达标普500指数人民币A'), quotaFamilyName('易方达标普500指数人民币C'));
    expect(quotaFamilyName('大成标普500等权重指数(QDII)A人民币'), '大成标普500等权重指数(QDII)');
    expect(quotaFamilyName('国泰纳斯达克100指数'), '国泰纳斯达克100指数');
    // Different fund products stay in different families.
    expect(quotaFamilyName('广发纳指100ETF联接(QDII)人民币F'), isNot(quotaFamilyName('广发纳斯达克100ETF联接人民币(QDII)A')));
  });

  test('parses status, amount, return and source fields', () {
    final result = EastmoneyQuotaSource.parse('''
      <div>交易状态：<span>限大额</span></div>
      <div>单日累计购买上限 2.5万 元</div>
      <div>近一年收益率：12.30%</div>
      <div>申购说明：仅限人民币份额申购。</div>
    ''', {'code': '012752', 'name': '建信纳斯达克100指数(QDII)A人民币'});
    expect(result['status'], '限大额');
    expect(result['limit'], 25000);
    expect(result['annualReturn'], closeTo(0.123, 0.00001));
    expect(result['sourceType'], 'public');
  });

  test('reads one-year return by fund code from Eastmoney data script', () async {
    final source = EastmoneyAnnualReturnSource(
      client: MockClient((request) async {
        expect(request.url.path, '/pingzhongdata/012752.js');
        return http.Response('var syl_1n="14.56";', 200);
      }),
    );
    expect(await source.fetch('012752'), closeTo(0.1456, 0.00001));
    expect(await source.fetch('bad'), isNull);
    source.close();
  });

  test('cloud repository reads the independent service and uploads corrections', () async {
    Map<String, dynamic>? uploadBody;
    final idempotencyKeys = <String>[];
    final repository = CloudQuotaRepository(
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'version': 4,
              'items': [
                {
                  'code': '000001',
                  'name': '测试纳指基金',
                  'category': '纳斯达克100',
                  'revision': 4,
                  'feeRate': 0.015,
                  'channels': {
                    'direct': {
                      'status': '开放申购',
                      'limit': 100,
                    },
                  },
                },
              ],
            })),
            200,
          );
        }
        uploadBody = jsonDecode(request.body) as Map<String, dynamic>;
        expect(request.headers['x-client-id'], startsWith('app-'));
        expect(request.headers['x-idempotency-key'], isNotEmpty);
        idempotencyKeys.add(request.headers['x-idempotency-key']!);
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'status': idempotencyKeys.length == 1 ? 'pending' : 'pending',
              'duplicate': idempotencyKeys.length > 1,
            }),
          ),
          idempotencyKeys.length == 1 ? 201 : 200,
        );
      }),
    );

    await repository.refresh();
    final before = (await repository.list()).single;
    expect(before['revision'], 4);
    expect(before['feeRate'], 0.015);
    await repository.setOverride('000001', {
      'channel': 'direct',
      'status': '限大额',
      'limit': 50,
    });
    final after = (await repository.list()).single;
    expect((after['channels'] as Map)['direct']['status'], '限大额');
    expect((after['channels'] as Map)['direct']['limit'], 50);
    final uploaded = await repository.uploadCorrection('000001', {
      'channel': 'direct',
      'status': '限大额',
      'limit': 50,
      'revision': 4,
    });
    expect(uploaded.status, 'pending');
    expect(uploadBody?['code'], '000001');
    expect(uploadBody?['baseRevision'], 4);
    final retried = await repository.uploadCorrection('000001', {
      'channel': 'direct',
      'status': '限大额',
      'limit': 50,
      'revision': 4,
    });
    expect(retried.duplicate, isTrue);
    expect(idempotencyKeys, hasLength(2));
    expect(idempotencyKeys[1], idempotencyKeys[0]);
    repository.close();
  });

  test('clears a manual override after cloud data catches up', () async {
    var refreshCount = 0;
    final storage = _MemoryRepository();
    final repository = CloudQuotaRepository(
      open: () async => storage,
      client: MockClient((request) async {
        refreshCount++;
        final limit = refreshCount == 1 ? 50 : 10;
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'version': refreshCount,
            'items': [
              {
                'code': '000001',
                'name': '测试纳指基金',
                'category': '纳斯达克100',
                'channels': {
                  'direct': {'status': '限大额', 'limit': limit},
                },
              },
            ],
          })),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
      annualReturnSource: EastmoneyAnnualReturnSource(
        client: MockClient((request) async => http.Response('', 500)),
      ),
    );

    await repository.refresh();
    await repository.setOverride('000001', {
      'channel': 'direct',
      'status': '限大额',
      'limit': 10,
    });
    expect((await repository.list()).single['valueSource'], 'user');

    await repository.refresh();

    final item = (await repository.list()).single;
    expect(item['valueSource'], 'automatic');
    expect(await storage.list('quotaOverrides'), isEmpty);
    expect(repository.takeUpdateNotice(), isNull);
    repository.close();
  });
}
