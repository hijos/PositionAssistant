const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'position-quotas-'));
process.env.POSITIONASSISTANT_DB_PATH = path.join(dir, 'db.json');
fs.writeFileSync(process.env.POSITIONASSISTANT_DB_PATH, JSON.stringify({
  users: [], funds: [], transactions: [], plans: [], quotas: [{
    code: '000003', name: '纳斯达克100指数QDII', category: '纳斯达克100', status: '开放申购', limit: 1000,
    annualReturn: 0.1, source: '自动测试源', updatedAt: '2026-09-25'
  }], fundCatalog: []
}));
const { app } = require('../server');

async function request(base, method, route, token, body) {
  const response = await fetch(base + route, {
    method,
    headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...(body ? { 'Content-Type': 'application/json' } : {}) },
    ...(body ? { body: JSON.stringify(body) } : {})
  });
  return { status: response.status, body: await response.json().catch(() => null) };
}

test('额度覆盖按账号隔离并保留自动基线', async t => {
  const server = app.listen(0);
  t.after(() => { server.close(); fs.rmSync(dir, { recursive: true, force: true }); });
  const base = `http://127.0.0.1:${server.address().port}`;
  assert.equal((await request(base, 'GET', '/api/quotas')).status, 401);
  const register = async email => request(base, 'POST', '/api/auth/register', null, { email, password: 'Quota-pass-1' });
  const login = async email => (await request(base, 'POST', '/api/auth/login', null, { email, password: 'Quota-pass-1' })).body.token;
  assert.equal((await register('quota-a@example.com')).status, 201);
  assert.equal((await register('quota-b@example.com')).status, 201);
  const a = await login('quota-a@example.com'); const b = await login('quota-b@example.com');
  const initial = await request(base, 'GET', '/api/quotas', a);
  assert.deepEqual({ status: initial.body[0].status, limit: initial.body[0].limit, priority: initial.body[0].priority }, { status: '开放申购', limit: 1000, priority: 'automatic' });
  const changedA = await request(base, 'PUT', '/api/quotas/000003', a, { status: '暂停申购' });
  assert.equal(changedA.status, 200);
  assert.deepEqual({ status: changedA.body.status, limit: changedA.body.limit, automaticLimit: changedA.body.automaticLimit, priority: changedA.body.priority }, { status: '暂停申购', limit: 1000, automaticLimit: 1000, priority: 'user' });
  const bAfterA = await request(base, 'GET', '/api/quotas', b);
  assert.deepEqual({ status: bAfterA.body[0].status, limit: bAfterA.body[0].limit, priority: bAfterA.body[0].priority }, { status: '开放申购', limit: 1000, priority: 'automatic' });
  const changedB = await request(base, 'PUT', '/api/quotas/000003', b, { limit: 200 });
  assert.deepEqual({ status: changedB.body.status, limit: changedB.body.limit, priority: changedB.body.priority }, { status: '开放申购', limit: 200, priority: 'user' });
  const aAfterB = await request(base, 'GET', '/api/quotas', a);
  assert.deepEqual({ status: aAfterB.body[0].status, limit: aAfterB.body[0].limit }, { status: '暂停申购', limit: 1000 });
  assert.equal((await request(base, 'PUT', '/api/quotas/000003', a, { limit: -1 })).status, 400);
  assert.equal((await request(base, 'PUT', '/api/quotas/000003', a, {})).status, 400);

  const realFetch = global.fetch;
  t.after(() => { global.fetch = realFetch; });
  global.fetch = async (url, options) => {
    if (String(url).startsWith('https://fund.eastmoney.com/')) {
      return new Response('<div>交易状态：<span class="staticCell">限大额</span></div><p>单日累计购买上限 800 元</p><p>近一年收益率：12.5%</p>');
    }
    return realFetch(url, options);
  };
  const restoredA = await request(base, 'POST', '/api/quotas/000003/restore', a);
  assert.equal(restoredA.status, 200);
  assert.deepEqual({ status: restoredA.body.status, limit: restoredA.body.limit, priority: restoredA.body.priority }, { status: '限大额', limit: 800, priority: 'automatic' });
  const bAfterRestore = await request(base, 'GET', '/api/quotas', b);
  assert.deepEqual({ status: bAfterRestore.body[0].status, limit: bAfterRestore.body[0].limit, automaticLimit: bAfterRestore.body[0].automaticLimit, priority: bAfterRestore.body[0].priority }, { status: '限大额', limit: 200, automaticLimit: 800, priority: 'user' });
  assert.equal((await request(base, 'POST', '/api/quotas/unknown/restore', a)).status, 404);

  await request(base, 'PUT', '/api/quotas/000003', a, { status: '暂停申购' });
  global.fetch = async (url, options) => {
    if (String(url).startsWith('https://fund.eastmoney.com/')) throw new Error('upstream unavailable');
    return realFetch(url, options);
  };
  assert.equal((await request(base, 'POST', '/api/quotas/000003/restore', a)).status, 502);
  const aAfterFailure = await request(base, 'GET', '/api/quotas', a);
  assert.deepEqual({ status: aAfterFailure.body[0].status, priority: aAfterFailure.body[0].priority }, { status: '暂停申购', priority: 'user' });
});
