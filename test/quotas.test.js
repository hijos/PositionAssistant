const test = require('node:test');
const assert = require('node:assert/strict');
const { amountFromText, classifyFund, isCandidate, parseQuotaPage, mergeAutomaticQuotas, restoreAutomaticQuota, visibleQuotas } = require('../server/quotas');

test('额度采集分类与金额解析', () => {
  assert.equal(classifyFund('某纳斯达克100指数QDII'), '纳斯达克100');
  assert.equal(classifyFund('某标普500指数'), '标普500');
  assert.equal(classifyFund('普通债券基金'), null);
  assert.equal(isCandidate({ name: '纳斯达克100指数QDII' }), true);
  assert.equal(isCandidate({ name: '纳斯达克100美元份额QDII' }), false);
  assert.equal(amountFromText('1.5万'), null);
  assert.equal(amountFromText('1.5万元'), 15000);
  assert.equal(amountFromText('2亿元'), 200000000);
});

test('额度页面解析及用户覆盖保留', () => {
  const fund = { code: '000001', name: '纳斯达克100指数QDII' };
  const parsed = parseQuotaPage('<div>交易状态：<span class="staticCell">限大额</span></div><p>单日累计购买上限 2 万元</p>', fund);
  assert.equal(parsed.category, '纳斯达克100');
  assert.equal(parsed.status, '限大额');
  assert.equal(parsed.limit, 20000);
  const fallback = parseQuotaPage('<div>交易状态：<span class="staticCell">开放申购</span></div>', { code: '021000', name: '纳斯达克100指数QDII' }, { '021000': { limit: 200, source: '公告', sourceType: 'announcement', sourceUrl: 'https://example.test' } });
  assert.equal(fallback.limit, 200);
  const merged = mergeAutomaticQuotas([parsed], [{ code: '000001', status: '暂停申购', limit: 100, userOverride: true, userId: 'u1' }]);
  assert.equal(merged[0].status, '暂停申购');
  assert.equal(merged[0].limit, 100);
  assert.equal(merged[0].automaticStatus, '限大额');
  assert.equal(merged[0].userId, 'u1');
});

test('额度解析保留收益率与详情字段', () => {
  const parsed = parseQuotaPage('<div>交易状态：<span class="staticCell">开放申购</span></div><p>单日累计购买上限 2 万元</p><p>近一年收益率：12.5%</p><p>申购说明：仅限人民币份额，详情以公告为准。</p>', { code: '000002', name: '标普500指数QDII' });
  assert.equal(parsed.annualReturn, 0.125);
  assert.equal(parsed.detail, '仅限人民币份额，详情以公告为准');
});

test('用户覆盖按账号隔离且优先于自动值', () => {
  const automatic = { code: '000003', name: '纳斯达克100指数QDII', category: '纳斯达克100', status: '开放申购', limit: 1000 };
  const old = [
    { ...automatic, userOverride: true, userId: 'u1', status: '暂停申购', limit: 100, automaticStatus: '开放申购', automaticLimit: 1000, overrideFields: ['status', 'limit'] },
    { ...automatic, userOverride: true, userId: 'u2', status: '限大额', limit: 200, automaticStatus: '开放申购', automaticLimit: 1000, overrideFields: ['limit'] }
  ];
  const merged = mergeAutomaticQuotas([automatic], old);
  const u1 = visibleQuotas(merged, 'u1').find(x => x.code === automatic.code);
  const u2 = visibleQuotas(merged, 'u2').find(x => x.code === automatic.code);
  const other = visibleQuotas(merged, 'other').find(x => x.code === automatic.code);
  assert.deepEqual({ status: u1.status, limit: u1.limit, priority: u1.priority }, { status: '暂停申购', limit: 100, priority: 'user' });
  assert.deepEqual({ status: u2.status, limit: u2.limit, priority: u2.priority }, { status: '开放申购', limit: 200, priority: 'user' });
  assert.deepEqual({ status: other.status, limit: other.limit, priority: other.priority }, { status: '开放申购', limit: 1000, priority: 'automatic' });
  assert.equal(other.userOverride, false);
});

test('恢复自动额度删除当前账号覆盖并更新其他账号自动基线', () => {
  const old = [
    { code: '000003', name: '旧名称', status: '开放申购', limit: 1000 },
    { code: '000003', name: '旧名称', status: '暂停申购', limit: 100, userOverride: true, userId: 'u1', automaticStatus: '开放申购', automaticLimit: 1000, overrideFields: ['status', 'limit'] },
    { code: '000003', name: '旧名称', status: '开放申购', limit: 200, userOverride: true, userId: 'u2', automaticStatus: '开放申购', automaticLimit: 1000, overrideFields: ['limit'] }
  ];
  const fresh = { code: '000003', name: '新名称', status: '限大额', limit: 800, category: '纳斯达克100' };
  const restored = restoreAutomaticQuota(old, fresh, 'u1');
  const visibleU1 = visibleQuotas(restored, 'u1')[0];
  const visibleU2 = visibleQuotas(restored, 'u2')[0];
  assert.equal(visibleU1.valueSource, 'automatic');
  assert.deepEqual({ status: visibleU1.status, limit: visibleU1.limit }, { status: '限大额', limit: 800 });
  assert.deepEqual({ status: visibleU2.status, limit: visibleU2.limit, automaticLimit: visibleU2.automaticLimit }, { status: '限大额', limit: 200, automaticLimit: 800 });
});
