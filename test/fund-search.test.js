const { test } = require('node:test');
const assert = require('node:assert/strict');
const { supportedFund, searchFunds, queryText, searchHandler } = require('../server/catalog/search');
const fund = (name, type = '混合型-偏股', code = '000001') => ({ name, type, code, shortName: 'CSJJ' });
test('RMB OTC policy excludes foreign shares, listed funds and unknown types', () => {
  for (const name of ['测试美元A', '测试港元', '测试USD', '测试LOF', '测试ETF', '测试封闭基金', '测试REIT']) assert.equal(supportedFund(fund(name)), false, name);
  assert.equal(supportedFund(fund('测试', '未知')), false);
  assert.equal(supportedFund(fund('测试', '场内基金')), false);
  for (const name of ['测试人民币A', '测试C', '测试ETF联接A']) assert.equal(supportedFund(fund(name)), true, name);
  assert.equal(supportedFund(fund('纳斯达克100人民币', 'QDII-普通股票')), true);
});
test('search normalizes input, matches names/codes, filters before limiting and keeps catalog intact', () => {
  const items = [fund('测试美元'), ...Array.from({ length: 30 }, (_, i) => fund('测试ETF联接C', '指数型-股票', String(i + 2).padStart(6, '0')))];
  assert.equal(searchFunds(items, queryText(' 测试 ')).length, 20);
  assert.equal(searchFunds(items, '000031')[0].code, '000031');
  assert.equal(searchFunds(items, queryText('ｃｓｊｊ')).length, 20);
  assert.deepEqual(searchFunds(items, ''), []);
  assert.deepEqual(searchFunds(items, '不存在'), []);
  assert.equal(items.length, 31);
  for (const query of [[], {}, 'x'.repeat(101)]) assert.throws(() => queryText(query));
});
test('HTTP search handles empty/invalid input, supported results, cache fallback and unavailable service', async () => {
  const express = require('express'); let calls = 0, fail = false;
  const app = express(); app.get('/api/funds/search', searchHandler({ async get() {
    calls++; if (fail) throw Error('secret');
    return { stale: true, items: [fund('测试'), fund('测试美元')] };
  } }));
  const server = app.listen(0, '127.0.0.1'); await new Promise(resolve => server.once('listening', resolve));
  const get = q => fetch(`http://127.0.0.1:${server.address().port}/api/funds/search${q}`);
  try {
    assert.deepEqual(await (await get('')).json(), []); assert.equal(calls, 0);
    assert.equal((await get('?q=a&q=b')).status, 400);
    assert.deepEqual(await (await get('?q=000001')).json(), [fund('测试')]);
    fail = true; const response = await get('?q=1'); assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), { error: '基金目录暂时不可用，且无可用缓存' });
  } finally { await new Promise(resolve => server.close(resolve)); }
});
