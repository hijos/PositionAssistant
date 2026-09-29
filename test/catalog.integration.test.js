const { test } = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { Client } = require('pg');
const { migrate, readMigrations } = require('../server/db/migrate');
const { FundStore } = require('../server/funds');
const { postgresStore, createCatalogService } = require('../server/catalog');
test('PostgreSQL catalog persists across connections and preserves cache on upstream failure', { skip: !process.env.TEST_DATABASE_URL }, async () => {
  const admin = new Client({ connectionString: process.env.TEST_DATABASE_URL });
  const database = `f11_test_${randomUUID().replaceAll('-', '')}`;
  const clients = []; let created = false;
  try {
    await admin.connect(); await admin.query(`CREATE DATABASE "${database}"`); created = true;
    const url = new URL(process.env.TEST_DATABASE_URL); url.pathname = `/${database}`;
    for (let i = 0; i < 2; i++) {
      const client = new Client({ connectionString: url.toString() }); clients.push(client); await client.connect();
    }
    await migrate(clients[0], await readMigrations());
    const fundsA = new FundStore(clients[0]), fundsB = new FundStore(clients[1]);
    const fund = {code:'000001',name:'测试基金A',type:'混合型'};
    await Promise.all(Array.from({length:8},(_,i)=>(i%2?fundsA:fundsB).add('alice',fund)));
    assert.deepEqual(await fundsB.list('alice'),[fund]);
    assert.deepEqual(await fundsB.list('bob'),[]);
    await fundsB.add('bob',fund);
    assert.deepEqual(await fundsA.list('bob'),[fund]);
    let calls = 0, time = 100000;
    const adapter = { id: 'fixture', sourceUrl: 'https://example.com', async fetchCatalog() {
      calls++; return [{ code: '000001', name: '测试基金', shortName: 'CS', type: '混合' }];
    } };
    const first = await createCatalogService({ adapter, store: postgresStore(clients[0]), now: () => time }).get();
    const service = createCatalogService({ adapter, store: postgresStore(clients[1]), now: () => time });
    assert.deepEqual(await service.get(), first); assert.equal(calls, 1);
    time += 86400001; adapter.fetchCatalog = async () => { throw Error('offline'); };
    assert.equal((await service.get()).stale, true);
    assert.equal((await postgresStore(clients[1]).read(adapter.id)).fetchedAt, first.fetchedAt);
  } finally {
    await Promise.all(clients.map(client => client.end()));
    if (created) await admin.query(`DROP DATABASE "${database}"`);
    await admin.end();
  }
});
