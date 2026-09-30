import 'package:flutter_test/flutter_test.dart';
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
}
