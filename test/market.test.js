const { test } = require('node:test');
const assert = require('node:assert/strict');
const { validateSymbol, yahooMarketAdapter, postgresStore, createMarketService, installMarketRoutes } = require('../server/market');

const chartBody = {
  chart: {
    result: [{
      meta: { exchangeTimezoneName: 'America/New_York' },
      timestamp: [Date.parse('2026-09-22T13:30:00Z') / 1000, Date.parse('2026-09-23T13:30:00Z') / 1000],
      indicators: { quote: [{ close: [22000.5, 22100.25] }] },
    }],
    error: null,
  },
};

test('yahoo adapter parses validated daily bars without executing scripts', async () => {
  const adapter = yahooMarketAdapter(async url => ({ ok: true, url, json: async () => chartBody }));
  const rows = await adapter.fetchHistory('^NDX');
  assert.deepEqual(rows.map(x => x.date), ['2026-09-23', '2026-09-22']);
  assert.deepEqual(rows.map(x => x.price), [22100.25, 22000.5]);
  assert.equal(rows[0].source, 'yahoo-chart-v1');
  assert.equal(rows[0].symbol, '^NDX');
});

test('adapter rejects invalid envelopes, empty series and bad symbols', async () => {
  const bad = yahooMarketAdapter(async () => ({ ok: true, json: async () => ({ chart: { result: [], error: { code: 'Not Found' } } }) }));
  await assert.rejects(() => bad.fetchHistory('^NDX'), /行情响应无效/);
  const empty = yahooMarketAdapter(async () => ({ ok: true, json: async () => ({ chart: { result: [{ meta: {}, timestamp: [], indicators: { quote: [{ close: [] }] } }], error: null } }) }));
  await assert.rejects(() => empty.fetchHistory('^NDX'), /无有效记录/);
  const http = yahooMarketAdapter(async () => ({ ok: false, status: 429, json: async () => ({}) }));
  await assert.rejects(() => http.fetchHistory('^NDX'), /429/);
  assert.throws(() => validateSymbol('CNY=X;DROP TABLE'), /行情代码无效/);
});

test('service caches history, refreshes after ttl and preserves stale cache on failure', async () => {
  let clock = Date.parse('2026-09-24T00:00:00Z'), calls = 0, saved = [];
  const store = { async history() { return saved; }, async write(symbol, values) { saved = values.map(x => ({ ...x, fetched_at: x.fetchedAt, trade_date: x.date })); } };
  const adapter = { id: 'fixture', async fetchHistory() { calls++; return [{ symbol: '^NDX', date: '2026-09-24', price: 22000, source: 'fixture', sourceUrl: 'x', fetchedAt: new Date(clock).toISOString() }]; } };
  const service = createMarketService({ adapter, store, now: () => clock, ttlMs: 1000 });
  assert.equal((await service.quote('^NDX')).price, 22000); assert.equal(calls, 1);
  assert.equal((await service.quote('^NDX')).price, 22000); assert.equal(calls, 1);
  clock += 2000; adapter.fetchHistory = async () => { calls++; throw Error('offline'); };
  const stale = await service.quote('^NDX', { refresh: true });
  assert.equal(stale.stale, true); assert.equal(stale.price, 22000); assert.equal(calls, 2);
});

test('concurrent refreshes are coalesced and missing cache raises an error', async () => {
  let calls = 0, release;
  const gate = new Promise(resolve => { release = resolve; });
  const store = { async history() { return []; }, async write() {} };
  const adapter = { id: 'fixture', async fetchHistory() { calls++; await gate; return [{ symbol: 'CNY=X', date: '2026-09-24', price: 7.1, source: 'fixture', sourceUrl: 'x', fetchedAt: new Date().toISOString() }]; } };
  const service = createMarketService({ adapter, store });
  const pair = [service.quote('CNY=X'), service.quote('CNY=X')];
  release();
  await Promise.all(pair);
  assert.equal(calls, 1);
  const failing = createMarketService({ adapter: { id: 'f2', async fetchHistory() { throw Error('down'); } }, store });
  await assert.rejects(() => failing.quote('CNY=X'));
});

test('service and PostgreSQL store keep adapter sources isolated', async () => {
  const calls = [];
  const pool = { async query(sql, args) { calls.push({ sql, args }); return { rows: [] }; } };
  const store = postgresStore(pool);
  await store.latest('^NDX', 'adapter-a');
  await store.history('^NDX', 60, 'adapter-a');
  await store.write('^NDX', [{ date: '2026-09-24', price: 22000, source: 'adapter-a', sourceUrl: 'x', fetchedAt: '2026-09-24T00:00:00.000Z' }], 'adapter-a');
  assert.deepEqual(calls[0].args, ['^NDX', 'adapter-a']);
  assert.match(calls[0].sql, /WHERE symbol=\$1 AND source=\$2/);
  assert.deepEqual(calls[1].args, ['^NDX', 'adapter-a', 60]);
  assert.match(calls[1].sql, /WHERE symbol=\$1 AND source=\$2/);
  await assert.rejects(() => store.write('^NDX', [{ date: '2026-09-24', price: 22000, source: 'adapter-b', sourceUrl: 'x', fetchedAt: '2026-09-24T00:00:00.000Z' }], 'adapter-a'), /行情来源无效/);

  let saved = [];
  const seen = [];
  const service = createMarketService({
    adapter: { id: 'adapter-a', async fetchHistory() { return [{ symbol: '^NDX', date: '2026-09-24', price: 22000, source: 'adapter-a', sourceUrl: 'x', fetchedAt: '2026-09-24T00:00:00.000Z' }]; } },
    store: {
      async history(...args) { seen.push(['history', ...args]); return saved; },
      async write(...args) { seen.push(['write', ...args]); saved = args[1]; },
    },
  });
  await service.history('^NDX');
  assert.deepEqual(seen.map(([method, symbol, limit, source]) => [method, symbol, limit, source]), [
    ['history', '^NDX', 60, 'adapter-a'],
    ['write', '^NDX', saved, 'adapter-a'],
    ['history', '^NDX', 60, 'adapter-a'],
  ]);
});

test('HTTP routes expose quote and history with controlled errors', async () => {
  const express = require('express'); const app = express();
  installMarketRoutes(app, {
    quote: async symbol => { if (symbol === '^GSPC') throw Error('down'); return { symbol, price: 1, date: '2026-09-24' }; },
    history: async () => ({ items: [], stale: false }),
  });
  const server = app.listen(0); await new Promise(resolve => server.once('listening', resolve));
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    assert.equal((await fetch(`${base}/api/market/${encodeURIComponent('^NDX')}/quote`)).status, 200);
    assert.equal((await fetch(`${base}/api/market/${encodeURIComponent('CNY=X')}/history`)).status, 200);
    assert.equal((await fetch(`${base}/api/market/${encodeURIComponent('^GSPC')}/quote`)).status, 502);
    assert.equal((await fetch(`${base}/api/market/AAPL/quote`)).status, 400);
  } finally { await new Promise(resolve => server.close(resolve)); }
});
