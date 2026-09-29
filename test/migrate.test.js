const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { readMigrations, migrate } = require('../server/db/migrate');

function fake(rows = [], fail = false) {
  const calls = [];
  return { calls, async query(sql, params) {
    calls.push({ sql, params });
    if (sql.startsWith('SELECT version')) return { rows };
    if (fail && sql.startsWith('-- F04')) throw new Error('SQL failure');
    return { rows: [] };
  } };
}
test('initialization records checksum and locks before inspecting history', async () => {
  const migrations = await readMigrations();
  const client = fake();
  assert.deepEqual(await migrate(client, migrations), migrations.map(m => m.name));
  assert.match(client.calls[1].sql, /pg_advisory_xact_lock/);
  assert.deepEqual(client.calls.find(c => c.params).params, [migrations[0].version, migrations[0].name, migrations[0].checksum]);
  assert.equal(client.calls.at(-1).sql, 'COMMIT');
});
test('repeat run does not execute migration SQL', async () => {
  const migrations = await readMigrations();
  const client = fake(migrations);
  assert.deepEqual(await migrate(client, migrations), []);
  assert.ok(!client.calls.some(c => c.sql === migrations[0].sql));
});
test('SQL failure rolls back and does not record success', async () => {
  const client = fake([], true);
  await assert.rejects(migrate(client, await readMigrations()), /SQL failure/);
  assert.equal(client.calls.at(-1).sql, 'ROLLBACK');
  assert.ok(!client.calls.some(c => c.sql.startsWith('INSERT')));
});
test('changed, missing and reordered applied history is refused', async () => {
  const migrations = await readMigrations();
  for (const rows of [[{ ...migrations[0], checksum: 'changed' }], [{ ...migrations[0], version: '0000' }], [...migrations, { version: '9999' }]]) {
    const client = fake(rows);
    await assert.rejects(migrate(client, migrations), /history mismatch/);
    assert.equal(client.calls.at(-1).sql, 'ROLLBACK');
  }
});
test('loader rejects empty files, invalid names and duplicate versions', async () => {
  for (const entries of [{ 'bad.sql': 'SELECT 1' }, { '0001_a.sql': '' }, { '0001_a.sql': 'SELECT 1', '0001_b.sql': 'SELECT 2' }]) {
    const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'f04-'));
    try {
      for (const [name, sql] of Object.entries(entries)) await fs.writeFile(path.join(directory, name), sql);
      await assert.rejects(readMigrations(directory));
    } finally { await fs.rm(directory, { recursive: true }); }
  }
});
