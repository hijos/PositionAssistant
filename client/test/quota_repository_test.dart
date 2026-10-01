import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:position_assistant/data/quota_repository.dart';

void main() {
  test('classifies supported RMB Nasdaq and S&P QDII funds', () {
    expect(quotaCategory('建信纳斯达克100指数(QDII)A人民币'), '纳斯达克100');
    expect(quotaCategory('华夏标普500ETF联接(QDII)'), '标普500');
    expect(quotaCandidate({'name': '建信纳斯达克100指数(QDII)A人民币', 'type': 'QDII'}), isTrue);
    expect(quotaCandidate({'name': '纳斯达克100指数(QDII)美元', 'type': 'QDII'}), isFalse);
    expect(quotaCandidate({'name': '标普500 ETF', 'type': '指数型'}), isFalse);
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
}
