const { Client } = require('pg');
const { readMigrations, migrate } = require('../server/db/migrate');

async function main() {
  if (!process.env.DATABASE_URL && !process.env.POSTGRES_PASSWORD) {
    throw new Error('Set DATABASE_URL or POSTGRES_PASSWORD (see docs/development.md)');
  }
  const client = new Client(process.env.DATABASE_URL ? { connectionString: process.env.DATABASE_URL } : {
    host: process.env.POSTGRES_HOST || '127.0.0.1',
    port: Number(process.env.POSTGRES_PORT || 5432),
    database: process.env.POSTGRES_DB || 'positionassistant',
    user: process.env.POSTGRES_USER || 'positionassistant',
    password: process.env.POSTGRES_PASSWORD,
  });
  const migrations = await readMigrations();
  try {
    await client.connect();
    const applied = await migrate(client, migrations);
    console.log(applied.length ? `Applied: ${applied.join(', ')}` : 'Database is up to date');
  } finally {
    await client.end();
  }
}
main().catch(() => {
  // Avoid printing connection strings or credentials from driver errors.
  console.error('Migration failed. Check database connectivity and migration history; see docs/development.md.');
  process.exitCode = 1;
});
