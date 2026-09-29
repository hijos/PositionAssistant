const URL = 'https://fund.eastmoney.com/js/fundcode_search.js';

function validateItems(items) {
  if (!Array.isArray(items) || !items.length) throw new Error('Empty or invalid catalog');
  const codes = new Set();
  return items.map(item => {
    if (!item || !/^\d{6}$/.test(item.code) || codes.has(item.code) ||
        typeof item.name !== 'string' || !item.name.trim() ||
        typeof item.shortName !== 'string' || typeof item.type !== 'string') {
      throw new Error('Invalid catalog record');
    }
    codes.add(item.code);
    return { code: item.code, name: item.name.trim(), shortName: item.shortName.trim(), type: item.type.trim() };
  });
}

function eastmoneyAdapter(fetchImpl = fetch) {
  return {
    id: 'eastmoney-fundcode-v1', sourceUrl: URL,
    async fetchCatalog() {
      const response = await fetchImpl(URL, {
        headers: { 'User-Agent': 'Mozilla/5.0' }, signal: AbortSignal.timeout(10000),
      });
      if (!response.ok) throw new Error('Catalog upstream HTTP error');
      const text = await response.text();
      // Parse data only; never execute third-party JavaScript.
      const match = text.trim().match(/^var\s+r\s*=\s*(\[[\s\S]*\])\s*;?$/);
      if (!match) throw new Error('Invalid catalog envelope');
      const rows = JSON.parse(match[1]);
      if (!Array.isArray(rows)) throw new Error('Invalid catalog rows');
      return validateItems(rows.map(row => {
        if (!Array.isArray(row) || row.length < 4) throw new Error('Invalid catalog row');
        return { code: row[0], shortName: row[1], name: row[2], type: row[3] };
      }));
    },
  };
}

function postgresStore(pool) {
  return {
    async read(source) {
      const result = await pool.query('SELECT snapshot FROM positionassistant.fund_catalog_cache WHERE source = $1', [source]);
      return result.rows[0]?.snapshot || null;
    },
    async write(snapshot) {
      // A single upsert replaces the complete snapshot atomically.
      await pool.query(`INSERT INTO positionassistant.fund_catalog_cache (source, snapshot)
        VALUES ($1, $2::jsonb) ON CONFLICT (source) DO UPDATE SET snapshot = EXCLUDED.snapshot`,
      [snapshot.source, JSON.stringify(snapshot)]);
    },
  };
}

function createCatalogService({ adapter, store, now = Date.now, ttlMs = 86400000, retryMs = 60000 }) {
  if (!adapter?.id || !adapter.sourceUrl || typeof adapter.fetchCatalog !== 'function') throw new Error('Invalid catalog adapter');
  let cached = null;
  let pending = null;
  let retryAt = 0;
  function validateSnapshot(snapshot) {
    if (!snapshot || snapshot.source !== adapter.id || snapshot.sourceUrl !== adapter.sourceUrl ||
        !Number.isFinite(Date.parse(snapshot.fetchedAt))) throw new Error('Invalid cached snapshot');
    return { ...snapshot, items: validateItems(snapshot.items) };
  }
  function result(snapshot, stale, refreshError = null) {
    return structuredClone({ ...snapshot, stale, refreshError });
  }
  async function load() {
    try {
      if (!cached) {
        try {
          const stored = await store.read(adapter.id);
          if (stored) cached = validateSnapshot(stored);
        } catch {
          // The upstream catalog remains usable when the optional cache is unavailable.
        }
      }
      const age = cached ? now() - Date.parse(cached.fetchedAt) : Infinity;
      if (age >= 0 && age < ttlMs) return result(cached, false);
      const items = validateItems(await adapter.fetchCatalog());
      const snapshot = { source: adapter.id, sourceUrl: adapter.sourceUrl, fetchedAt: new Date(now()).toISOString(), items };
      try {
        await store.write(snapshot);
      } catch {
        // Keep serving the fresh in-memory snapshot when persistence is unavailable.
      }
      cached = snapshot;
      retryAt = 0;
      return result(cached, false);
    } catch {
      retryAt = now() + retryMs;
      if (cached) return result(cached, true, '目录刷新失败，正在使用旧缓存');
      throw new Error('基金目录暂时不可用，且无可用缓存');
    }
  }
  return {
    async get() {
      if (pending) return structuredClone(await pending);
      if (now() < retryAt) {
        if (cached) return result(cached, true, '目录刷新失败，正在使用旧缓存');
        throw new Error('基金目录暂时不可用，且无可用缓存');
      }
      pending = load();
      try { return structuredClone(await pending); } finally { pending = null; }
    },
  };
}

function configuredCatalogService(env = process.env) {
  const { Pool } = require('pg');
  const pool = new Pool({ ...(env.DATABASE_URL ? { connectionString: env.DATABASE_URL } : {
    host: env.POSTGRES_HOST || '127.0.0.1', port: Number(env.POSTGRES_PORT || 5432),
    database: env.POSTGRES_DB || 'positionassistant', user: env.POSTGRES_USER || 'positionassistant', password: env.POSTGRES_PASSWORD,
  }), connectionTimeoutMillis: 5000, query_timeout: 10000 });
  return createCatalogService({ adapter: eastmoneyAdapter(), store: postgresStore(pool) });
}
module.exports = { validateItems, eastmoneyAdapter, postgresStore, createCatalogService, configuredCatalogService };
