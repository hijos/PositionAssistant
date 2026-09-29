const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');

const defaultDirectory = path.join(__dirname, 'migrations');
async function readMigrations(directory = defaultDirectory) {
  const names = (await fs.readdir(directory)).filter(name => name.endsWith('.sql')).sort();
  if (!names.length) throw new Error('No SQL migrations found');
  const versions = new Set();
  return Promise.all(names.map(async name => {
    const match = /^(\d{4})_[a-z0-9_]+\.sql$/.exec(name);
    if (!match || versions.has(match[1])) throw new Error(`Invalid or duplicate migration: ${name}`);
    versions.add(match[1]);
    const sql = await fs.readFile(path.join(directory, name), 'utf8');
    if (!sql.trim()) throw new Error(`Empty migration: ${name}`);
    return { version: match[1], name, sql, checksum: crypto.createHash('sha256').update(sql).digest('hex') };
  }));
}

// Caller supplies a dedicated connected client; never a pool.query facade.
async function migrate(client, migrations) {
  await client.query('BEGIN');
  try {
    await client.query('SELECT pg_advisory_xact_lock(17492, 4)');
    await client.query(`CREATE TABLE IF NOT EXISTS public.schema_migrations (
      version text PRIMARY KEY, name text NOT NULL, checksum text NOT NULL,
      applied_at timestamptz NOT NULL DEFAULT now()
    )`);
    const { rows } = await client.query('SELECT version, name, checksum FROM public.schema_migrations ORDER BY version');
    // Applied history must be an exact prefix: refuse missing, edited or reordered migrations.
    for (let i = 0; i < rows.length; i++) {
      const expected = migrations[i];
      if (!expected || rows[i].version !== expected.version || rows[i].name !== expected.name || rows[i].checksum !== expected.checksum) {
        throw new Error(`Migration history mismatch at ${rows[i].version}`);
      }
    }
    const applied = [];
    for (const migration of migrations.slice(rows.length)) {
      await client.query(migration.sql);
      await client.query('INSERT INTO public.schema_migrations (version, name, checksum) VALUES ($1, $2, $3)',
        [migration.version, migration.name, migration.checksum]);
      applied.push(migration.name);
    }
    await client.query('COMMIT');
    return applied;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  }
}
module.exports = { readMigrations, migrate };
