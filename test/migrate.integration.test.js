const { test } = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { Client } = require('pg');
const { migrate, readMigrations } = require('../server/db/migrate');

test('PostgreSQL: empty database, repetition, concurrency, rollback and checksum protection', {
  skip: !process.env.TEST_DATABASE_URL,
}, async () => {
  // TEST_DATABASE_URL must point to a development admin with CREATEDB permission.
  const admin = new Client({ connectionString: process.env.TEST_DATABASE_URL });
  const database = `f04_test_${randomUUID().replaceAll('-', '')}`;
  let created = false;
  const clients = [];
  try {
    await admin.connect();
    await admin.query(`CREATE DATABASE "${database}"`);
    created = true;
    const url = new URL(process.env.TEST_DATABASE_URL);
    url.pathname = `/${database}`;
    for (let i = 0; i < 2; i++) {
      const client = new Client({ connectionString: url.toString() });
      clients.push(client);
      await client.connect();
    }
    const [a, b] = clients;
    const migrations = await readMigrations();
    const results = await Promise.all([migrate(a, migrations), migrate(b, migrations)]);
    assert.deepEqual(results.map(r => r.length).sort(), [0, 1]);
    assert.equal((await a.query("SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'positionassistant'")).rowCount, 1);
    const before = (await a.query('SELECT * FROM public.schema_migrations')).rows;
    assert.deepEqual(await migrate(a, migrations), []);
    assert.deepEqual((await a.query('SELECT * FROM public.schema_migrations')).rows, before);
    const failing = { version: '0002', name: '0002_failure.sql', checksum: 'test-only',
      sql: 'CREATE TABLE positionassistant.rollback_probe (id integer); SELECT 1 / 0;' };
    await assert.rejects(migrate(a, [...migrations, failing]));
    assert.equal((await a.query("SELECT to_regclass('positionassistant.rollback_probe') AS relation")).rows[0].relation, null);
    assert.deepEqual((await a.query('SELECT * FROM public.schema_migrations')).rows, before);
    await assert.rejects(migrate(a, [{ ...migrations[0], checksum: 'changed' }]), /history mismatch/);
  } finally {
    await Promise.all(clients.map(client => client.end()));
    if (created) await admin.query(`DROP DATABASE "${database}"`);
    await admin.end();
  }
});
