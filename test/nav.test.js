const { test } = require('node:test');
const assert = require('node:assert/strict');
const { eastmoneyNavAdapter, createNavService, installNavRoutes } = require('../server/nav');

const rows = [{ DWJZ: '1.2345', FSRQ: '2026-09-23' }, { DWJZ: '1.2', FSRQ: '2026-09-22' }];
test('official adapter parses validated history without executing scripts', async () => {
  const adapter = eastmoneyNavAdapter(async url => ({ ok: true, json: async () => ({ Data: { LSJZList: rows } }), url }));
  const result = await adapter.fetchHistory('000001');
  assert.deepEqual(result.map(x => x.nav), [1.2345, 1.2]);
  assert.equal(result[0].source, 'eastmoney-nav-v1');
});
test('service caches history, coalesces refresh and preserves stale cache on failure', async () => {
  let clock = Date.parse('2026-09-24T00:00:00Z'), calls = 0, saved = [];
  const store = { async history() { return saved; }, async write(code, values) { saved = values.map(x => ({ ...x, fetched_at: x.fetchedAt, nav_date: x.navDate })); } };
  const adapter = { id: 'fixture', async fetchHistory() { calls++; return [{ nav: 2, navDate: '2026-09-24', source: 'fixture', sourceUrl: 'x', fetchedAt: new Date(clock).toISOString() }]; } };
  const service = createNavService({ adapter, store, now: () => clock, ttlMs: 1000 });
  assert.equal((await service.latest('000001')).nav, 2); assert.equal(calls, 1);
  assert.equal((await service.latest('000001')).nav, 2); assert.equal(calls, 1);
  clock += 2000; adapter.fetchHistory = async () => { calls++; throw Error('offline'); };
  const stale = await service.latest('000001', { refresh: true });
  assert.equal(stale.stale, true); assert.equal(calls, 2);
});
test('HTTP routes expose latest and history with controlled errors', async () => {
  const express = require('express'); const app = express();
  installNavRoutes(app, { latest: async () => ({ nav: 1, navDate: '2026-09-24' }), history: async () => ({ items: [], stale: false }) });
  const server = app.listen(0); await new Promise(resolve => server.once('listening', resolve));
  try { const base = `http://127.0.0.1:${server.address().port}`; assert.equal((await fetch(`${base}/api/funds/000001/nav`)).status, 200); assert.equal((await fetch(`${base}/api/funds/000001/nav/history`)).status, 200); }
  finally { await new Promise(resolve => server.close(resolve)); }
});
