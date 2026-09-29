const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'position-import-'));
process.env.POSITIONASSISTANT_DB_PATH = path.join(dir, 'db.json');
const initial = {
  users: [], funds: [{ code: '160213', name: 'A', nav: 1 }],
  transactions: [], plans: [], planEntries: [], quotas: [], fundCatalog: []
};
fs.writeFileSync(process.env.POSITIONASSISTANT_DB_PATH, JSON.stringify(initial, null, 2));
const { app, summarizeImportPackage } = require('../server');

function call(port, method, route, body, token) {
  return new Promise((resolve, reject) => {
    const headers = {};
    if (body) headers['Content-Type'] = 'application/json';
    if (token) headers.Authorization = `Bearer ${token}`;
    const request = http.request({ port, method, path: route, headers }, response => {
      let text = '';
      response.on('data', chunk => { text += chunk; });
      response.on('end', () => resolve({ status: response.statusCode, body: text ? JSON.parse(text) : null }));
    });
    request.on('error', reject);
    if (body) request.write(JSON.stringify(body));
    request.end();
  });
}

const pkg = {
  format: 'position-assistant.export', version: 1, exportedAt: '2026-09-25T00:00:00.000Z',
  data: {
    funds: [{ code: '160213', name: 'A' }],
    transactions: [{ id: 't1', fundCode: '160213', status: 'confirmed' }],
    plans: [{ id: 'p1', fundCode: '160213' }],
    planEntries: [{ id: 'e1', planId: 'p1', status: 'pending' }],
    quotaOverrides: [{ code: '160213', limit: 100 }]
  }
};

test('导入包预检返回数据概要且不修改原数据', async t => {
  const server = app.listen(0);
  t.after(() => server.close());
  const port = server.address().port;
  assert.deepEqual(summarizeImportPackage(pkg).counts, {
    funds: 1, transactions: 1, plans: 1, planEntries: 1, quotaOverrides: 1, total: 5
  });
  assert.equal((await call(port, 'POST', '/api/import/preview', pkg)).status, 401);
  assert.equal((await call(port, 'POST', '/api/auth/register', { email: 'import@example.com', password: 'password-i' })).status, 201);
  const login = await call(port, 'POST', '/api/auth/login', { email: 'import@example.com', password: 'password-i' });
  const before = fs.readFileSync(process.env.POSITIONASSISTANT_DB_PATH, 'utf8');
  const result = await call(port, 'POST', '/api/import/preview', pkg, login.body.token);
  assert.equal(result.status, 200);
  assert.equal(result.body.valid, true);
  assert.equal(result.body.format, pkg.format);
  assert.equal(result.body.version, pkg.version);
  assert.deepEqual(result.body.summary.counts, { funds: 1, transactions: 1, plans: 1, planEntries: 1, quotaOverrides: 1, total: 5 });
  assert.deepEqual(result.body.summary.transactionStatuses, { confirmed: 1 });
  assert.equal(fs.readFileSync(process.env.POSITIONASSISTANT_DB_PATH, 'utf8'), before);
});

test('导入包格式错误时拒绝且不产生数据写入', () => {
  assert.throws(() => summarizeImportPackage({ ...pkg, version: 99 }), /版本不支持/);
  assert.throws(() => summarizeImportPackage({ ...pkg, data: { ...pkg.data, transactions: [null] } }), /只能包含 JSON 对象/);
});

test('远端导入按账号完整覆盖且失败回滚', async t => {
  const server = app.listen(0);
  t.after(() => { server.close(); fs.rmSync(dir, { recursive: true, force: true }); });
  const port = server.address().port;
  const login = await call(port, 'POST', '/api/auth/login', { email: 'import@example.com', password: 'password-i' });
  const token = login.body.token;
  const before = JSON.parse(fs.readFileSync(process.env.POSITIONASSISTANT_DB_PATH, 'utf8'));
  fs.writeFileSync(process.env.POSITIONASSISTANT_DB_PATH, JSON.stringify(before, null, 2));
  const result = await call(port, 'POST', '/api/import', pkg, token);
  assert.equal(result.status, 200);
  const after = JSON.parse(fs.readFileSync(process.env.POSITIONASSISTANT_DB_PATH, 'utf8'));
  assert.deepEqual(after.transactions.filter(x => x.userId === login.body.userId).map(x => x.id), ['t1']);
  const snapshot = fs.readFileSync(process.env.POSITIONASSISTANT_DB_PATH, 'utf8');
  const bad = { ...pkg, data: { ...pkg.data, planEntries: [{ id: 'e1', planId: 'missing', status: 'pending' }] } };
  assert.equal((await call(port, 'POST', '/api/import', bad, token)).status, 400);
  assert.equal(fs.readFileSync(process.env.POSITIONASSISTANT_DB_PATH, 'utf8'), snapshot);
});
