const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { createQuotaServiceApp } = require('../quota-service');

async function request(base, method, route, options = {}) {
  const response = await fetch(base + route, {
    method,
    headers: { ...(options.token ? { Authorization: `Bearer ${options.token}` } : {}), ...(options.body ? { 'Content-Type': 'application/json' } : {}), ...(options.headers || {}) },
    ...(options.body ? { body: JSON.stringify(options.body) } : {}),
  });
  return { status: response.status, body: await response.json().catch(() => null) };
}

test('independent quota service supports manual data, consensus and safe revoke', async t => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'quota-service-'));
  const dbPath = path.join(dir, 'db.json');
  const service = createQuotaServiceApp({ dbPath, adminPassword: 'test-secret', ipSalt: 'test-salt', trustProxy: true });
  const server = service.app.listen(0);
  t.after(() => { server.close(); fs.rmSync(dir, { recursive: true, force: true }); });
  const base = `http://127.0.0.1:${server.address().port}`;

  const login = await request(base, 'POST', '/api/admin/login', { body: { password: 'test-secret' } });
  assert.equal(login.status, 200);
  const token = login.body.token;
  assert.equal((await request(base, 'GET', '/api/quotas')).body.items.length, 0);
  const catalog = await request(base, 'GET', '/api/admin/fund-catalog', { token });
  assert.equal(catalog.status, 200);
  assert.ok(catalog.body.items.some(item => item.code === '012752'));

  const write = await request(base, 'PUT', '/api/admin/quotas/000001', { token, body: { name: '测试纳指基金', category: '纳斯达克100', channel: 'distribution', status: '限大额', limit: 100, feeRatePercent: 1.5 } });
  assert.equal(write.status, 200);
  assert.equal(write.body.item.feeRate, 0.015);
  assert.equal(write.body.item.channels.distribution.feeRate, undefined);

  const open = await request(base, 'PUT', '/api/admin/quotas/000001', { token, body: { channel: 'direct', status: '开放申购', limit: 999 } });
  assert.equal(open.body.item.channels.direct.limit, null);

  await request(base, 'PUT', '/api/admin/settings', { token, body: { minSupport: 2, agreementRatio: 0.8, windowHours: 72 } });
  const first = await request(base, 'POST', '/api/corrections', { headers: { 'x-forwarded-for': '192.0.2.1', 'x-client-id': 'a', 'x-idempotency-key': 'same-a' }, body: { code: '000001', channel: 'distribution', status: '限大额', limit: 50 } });
  assert.equal(first.status, 201);
  assert.equal(first.body.status, 'pending');
  const duplicate = await request(base, 'POST', '/api/corrections', { headers: { 'x-forwarded-for': '192.0.2.1', 'x-client-id': 'a', 'x-idempotency-key': 'same-a' }, body: { code: '000001', channel: 'distribution', status: '限大额', limit: 50 } });
  assert.equal(duplicate.body.duplicate, true);
  const second = await request(base, 'POST', '/api/corrections', { headers: { 'x-forwarded-for': '192.0.2.2', 'x-client-id': 'b', 'x-idempotency-key': 'same-b' }, body: { code: '000001', channel: 'distribution', status: '限大额', limit: 50 } });
  assert.equal(second.body.status, 'applied');
  assert.equal((await request(base, 'GET', '/api/quotas')).body.items[0].channels.distribution.limit, 50);

  const audit = (await request(base, 'GET', '/api/admin/audit', { token })).body.items.find(item => item.type === 'consensus-applied');
  assert.ok(audit);
  const revoked = await request(base, 'POST', `/api/admin/corrections/${audit.id}/revoke`, { token, body: { reason: '测试撤销' } });
  assert.equal(revoked.status, 200);
  assert.equal((await request(base, 'GET', '/api/quotas')).body.items[0].channels.distribution.limit, 100);
  assert.equal((await request(base, 'POST', `/api/admin/corrections/${audit.id}/revoke`, { token, body: {} })).status, 409);
});

test('admin endpoints require an admin session', async t => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'quota-service-auth-'));
  const service = createQuotaServiceApp({ dbPath: path.join(dir, 'db.json'), adminPassword: 'test-secret' });
  const server = service.app.listen(0);
  t.after(() => { server.close(); fs.rmSync(dir, { recursive: true, force: true }); });
  const base = `http://127.0.0.1:${server.address().port}`;
  assert.equal((await request(base, 'GET', '/api/admin/quotas')).status, 401);
  assert.equal((await request(base, 'POST', '/api/admin/login', { body: { password: 'bad' } })).status, 401);
});
