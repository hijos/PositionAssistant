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
  assert.ok(catalog.body.items.some(item => item.code === '019172'));
  const byCode = new Map(catalog.body.items.map(item => [item.code, item.name]));
  assert.equal(byCode.get('000834'), '大成纳斯达克100ETF联接(QDII)A');
  assert.equal(byCode.get('019172'), '摩根纳斯达克100指数(QDII)人民币A');
  assert.equal(byCode.get('019173'), '摩根纳斯达克100指数(QDII)人民币C');
  assert.equal(byCode.get('012752'), '建信纳斯达克100指数(QDII)C人民币');
  assert.equal(byCode.get('021778'), '广发纳指100ETF联接(QDII)人民币F');
  const nasdaqCodes = catalog.body.items.filter(item => item.category === '纳斯达克100').map(item => item.code);
  assert.equal(nasdaqCodes.length, 41);
  assert.equal(nasdaqCodes.includes('159513'), false);
  assert.equal(nasdaqCodes.includes('159659'), false);
  assert.ok(nasdaqCodes.includes('161130'));
  assert.equal(catalog.body.items.some(item => /ETF/.test(item.name) && !/(联接|连接)/.test(item.name)), false);
  const position = code => catalog.body.items.findIndex(item => item.code === code);
  assert.equal(position('008971'), position('000834') + 1);
  assert.equal(position('015300'), position('015299') + 1);
  assert.equal(position('019173'), position('019172') + 1);
  assert.equal(position('016453'), position('016452') + 1);
  assert.equal(byCode.has('008303'), false);
  assert.equal(byCode.has('020369'), false);
  assert.equal(byCode.has('040001'), false);
  assert.equal(new Set(catalog.body.items.map(item => item.code)).size, catalog.body.items.length);

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

  const pending = await request(base, 'POST', '/api/corrections', { headers: { 'x-forwarded-for': '192.0.2.3', 'x-client-id': 'c' }, body: { code: '000001', channel: 'distribution', status: '暂停申购', limit: null } });
  assert.equal(pending.body.status, 'pending');
  const correction = (await request(base, 'GET', '/api/admin/corrections', { token })).body.items.find(item => item.id === pending.body.id);
  assert.equal(correction.status, 'active');
  const accepted = await request(base, 'POST', `/api/admin/corrections/${pending.body.id}/accept`, { token, body: {} });
  assert.equal(accepted.status, 200);
  assert.equal(accepted.body.item.channels.distribution.status, '暂停申购');
  assert.equal((await request(base, 'GET', '/api/admin/audit', { token })).body.items[0].type, 'admin-accepted-suggestion');

  const removable = await request(base, 'POST', '/api/corrections', { headers: { 'x-forwarded-for': '192.0.2.4', 'x-client-id': 'd' }, body: { code: '000001', channel: 'distribution', status: '限大额', limit: 1 } });
  assert.equal((await request(base, 'DELETE', `/api/admin/corrections/${removable.body.id}`, { token })).status, 200);
  assert.equal((await request(base, 'GET', '/api/admin/corrections', { token })).body.items.some(item => item.id === removable.body.id), false);
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

test('admin can save both channels in one request', async t => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'quota-service-both-'));
  const service = createQuotaServiceApp({ dbPath: path.join(dir, 'db.json'), adminPassword: 'test-secret' });
  const server = service.app.listen(0);
  t.after(() => { server.close(); fs.rmSync(dir, { recursive: true, force: true }); });
  const base = `http://127.0.0.1:${server.address().port}`;
  const login = await request(base, 'POST', '/api/admin/login', { body: { password: 'test-secret' } });
  const token = login.body.token;

  const saved = await request(base, 'PUT', '/api/admin/quotas/012752', { token, body: { name: '测试基金', category: '纳斯达克100', feeRatePercent: 1.2, channels: { distribution: { status: '限大额', limit: 1000, sourceUrl: 'https://a.example' }, direct: { status: '开放申购' } } } });
  assert.equal(saved.status, 200);
  assert.equal(saved.body.item.channels.distribution.status, '限大额');
  assert.equal(saved.body.item.channels.distribution.limit, 1000);
  assert.equal(saved.body.item.channels.distribution.sourceUrl, 'https://a.example');
  assert.equal(saved.body.item.channels.direct.status, '开放申购');
  assert.equal(saved.body.item.channels.direct.limit, null);
  assert.equal(saved.body.item.feeRate, 0.012);

  const audit = (await request(base, 'GET', '/api/admin/audit', { token })).body.items;
  assert.equal(audit.length, 1);
  assert.equal(audit[0].channel, null);
  assert.deepEqual(audit[0].channels, ['distribution', 'direct']);
  assert.equal(audit[0].created, true);

  const update = await request(base, 'PUT', '/api/admin/quotas/012752', { token, body: { channels: { direct: { status: '暂停申购' } } } });
  assert.equal(update.status, 200);
  assert.equal(update.body.item.channels.distribution.limit, 1000);
  assert.equal(update.body.item.channels.direct.status, '暂停申购');
  const laterAudit = (await request(base, 'GET', '/api/admin/audit', { token })).body.items[0];
  assert.equal(laterAudit.type, 'manual-update');
  assert.equal(laterAudit.created, false);

  const badChannel = await request(base, 'PUT', '/api/admin/quotas/012752', { token, body: { channels: { whatever: { status: '限大额' } } } });
  assert.equal(badChannel.status, 400);
  const badStatus = await request(base, 'PUT', '/api/admin/quotas/012752', { token, body: { channels: { distribution: { status: '不限购' }, direct: { status: '限大额' } } } });
  assert.equal(badStatus.status, 400);
});
