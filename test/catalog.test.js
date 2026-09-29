const { test } = require('node:test');
const assert = require('node:assert/strict');
const { eastmoneyAdapter, createCatalogService, postgresStore } = require('../server/catalog');
const items = [{ code: '000001', name: '测试基金', shortName: 'CSJJ', type: '混合型' }];
function fixture() {
  let time = 100000, calls = 0, snapshot = null, failure = false;
  const adapter = { id: 'fixture', sourceUrl: 'https://example.com', async fetchCatalog() { calls++; if (failure) throw Error(); return items; } };
  const store = { async read() { return snapshot; }, async write(value) { snapshot = structuredClone(value); } };
  return { adapter, store, now: () => time, advance: () => { time += 86400001; }, fail: () => { failure = true; }, calls: () => calls, snapshot: () => snapshot };
}
test('adapter parses data without evaluating JavaScript and supplies timeout', async () => {
  const adapter = eastmoneyAdapter(async (url, options) => {
    assert.ok(options.signal instanceof AbortSignal);
    assert.equal(url, adapter.sourceUrl);
    return { ok: true, text: async () => 'var r = [["000001","CSJJ","测试基金","混合型","CESHI"]];' };
  });
  assert.deepEqual(await adapter.fetchCatalog(), items);
});
test('adapter rejects HTTP errors, script injection, empty, duplicate and malformed rows', async () => {
  for (const body of ['var r=[];', 'var r=[["1","a","b","c"]];', 'var r=[["000001","a","","c"]];',
    'var r=[["000001","a","b","c"],["000001","a","b","c"]];', 'var r=[];process.exit();', 'var r=[null];']) {
    await assert.rejects(eastmoneyAdapter(async () => ({ ok: true, text: async () => body })).fetchCatalog());
  }
  await assert.rejects(eastmoneyAdapter(async () => ({ ok: false })).fetchCatalog());
});
test('cold concurrent requests coalesce, cache survives service recreation, TTL refreshes', async () => {
  const f = fixture(), service = createCatalogService(f);
  const values = await Promise.all(Array.from({ length: 10 }, () => service.get()));
  assert.equal(f.calls(), 1);
  values[0].items[0].name = 'mutated';
  assert.equal((await service.get()).items[0].name, '测试基金');
  await createCatalogService(f).get();
  assert.equal(f.calls(), 1);
  f.advance();
  assert.equal((await service.get()).stale, false);
  assert.equal(f.calls(), 2);
});
test('refresh failure retains timestamp and durable snapshot with retry cooldown', async () => {
  const f = fixture(), service = createCatalogService(f);
  const first = await service.get(); f.advance(); f.fail();
  const old = await service.get();
  assert.equal(old.stale, true); assert.ok(old.refreshError);
  assert.equal(old.fetchedAt, first.fetchedAt);
  assert.deepEqual(f.snapshot().items, items);
  await service.get(); assert.equal(f.calls(), 2);
});
test('cold failure is explicit; no seed fallback; malformed replacement never overwrites cache', async () => {
  const f = fixture(); f.fail();
  await assert.rejects(createCatalogService(f).get(), /无可用缓存/);
  const good = fixture(), service = createCatalogService(good);
  await service.get(); good.advance(); good.adapter.fetchCatalog = async () => [];
  assert.equal((await service.get()).stale, true);
  assert.deepEqual(good.snapshot().items, items);
});
test('write failure preserves previous snapshot; adapters use independent cache keys', async () => {
  const f = fixture(), service = createCatalogService(f); const initial = await service.get();
  f.advance(); f.store.write = async () => { throw Error(); };
  assert.equal((await service.get()).fetchedAt, initial.fetchedAt);
  const keys = [];
  const store = { async read(key) { keys.push(key); return null; }, async write() {} };
  await createCatalogService({ ...f, store, adapter: { ...f.adapter, id: 'replacement' } }).get();
  assert.deepEqual(keys, ['replacement']);
});
test('PostgreSQL store uses parameterized snapshot read and atomic upsert', async () => {
  const calls = [], snapshot = { source: 'fixture', items };
  const store = postgresStore({ async query(sql, args) { calls.push({ sql, args }); return { rows: [{ snapshot }] }; } });
  assert.deepEqual(await store.read('fixture'), snapshot);
  await store.write(snapshot);
  assert.deepEqual(calls[0].args, ['fixture']);
  assert.match(calls[1].sql, /ON CONFLICT/);
  assert.deepEqual(JSON.parse(calls[1].args[1]), snapshot);
});
test('HTTP catalog endpoint returns metadata and controlled unavailable response', async () => {
  const express = require('express');
  const { catalogHandler } = require('../server/catalog/route');
  let fail = false;
  const app = express();
  app.get('/api/fund-catalog', catalogHandler({ async get() {
    if (fail) throw Error('private connection details');
    return { items, source: 'fixture', fetchedAt: '2026-09-13T00:00:00.000Z', stale: true };
  } }));
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  try {
    const url = `http://127.0.0.1:${server.address().port}/api/fund-catalog`;
    const response = await fetch(url);
    assert.equal(response.status, 200); assert.equal((await response.json()).stale, true);
    fail = true;
    const unavailable = await fetch(url);
    assert.equal(unavailable.status, 503);
    assert.deepEqual(await unavailable.json(), { error: '基金目录暂时不可用，且无可用缓存' });
  } finally { await new Promise(resolve => server.close(resolve)); }
});
