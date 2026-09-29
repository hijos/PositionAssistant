const DEFAULT_URL = 'https://api.fund.eastmoney.com/f10/lsjz';

function validateCode(code) {
  if (typeof code !== 'string' || !/^\d{6}$/.test(code)) throw new Error('基金代码无效');
  return code;
}

function normalizeRow(row, source, sourceUrl, fetchedAt) {
  const nav = Number(row?.DWJZ ?? row?.nav);
  const navDate = String(row?.FSRQ ?? row?.navDate ?? '');
  if (!Number.isFinite(nav) || nav <= 0 || !/^\d{4}-\d{2}-\d{2}$/.test(navDate)) throw new Error('净值记录无效');
  return { nav, navDate, source, sourceUrl, fetchedAt };
}

function eastmoneyNavAdapter(fetchImpl = fetch) {
  return {
    id: 'eastmoney-nav-v1', sourceUrl: DEFAULT_URL,
    async fetchHistory(code, { startDate, endDate } = {}) {
      validateCode(code);
      const params = { fundCode: code, pageIndex: '1', pageSize: '100' };
      if (startDate) params.startDate = startDate;
      if (endDate) params.endDate = endDate;
      const url = `${DEFAULT_URL}?${new URLSearchParams(params)}`;
      const response = await fetchImpl(url, { headers: { Referer: 'https://fund.eastmoney.com/' }, signal: AbortSignal.timeout(10000) });
      if (!response.ok) throw new Error(`净值接口 ${response.status}`);
      const body = await response.json();
      if (!Array.isArray(body?.Data?.LSJZList)) throw new Error('净值响应无效');
      const fetchedAt = new Date().toISOString();
      return body.Data.LSJZList.map(row => normalizeRow(row, this.id, this.sourceUrl, fetchedAt));
    },
  };
}

function postgresStore(pool) {
  const mapRow = row => ({ nav: Number(row.nav), navDate: String(row.nav_date).slice(0, 10), source: row.source, sourceUrl: row.source_url, fetchedAt: new Date(row.fetched_at).toISOString() });
  return {
    async latest(code) {
      const r = await pool.query('SELECT nav, nav_date, source, source_url, fetched_at FROM positionassistant.nav_snapshots WHERE code=$1 ORDER BY nav_date DESC, fetched_at DESC LIMIT 1', [code]);
      return r.rows[0] ? mapRow(r.rows[0]) : null;
    },
    async history(code, limit = 100) {
      const r = await pool.query('SELECT nav, nav_date, source, source_url, fetched_at FROM positionassistant.nav_snapshots WHERE code=$1 ORDER BY nav_date DESC LIMIT $2', [code, limit]);
      return r.rows.map(mapRow);
    },
    async write(code, rows) {
      for (const row of rows) await pool.query(`INSERT INTO positionassistant.nav_snapshots(code, nav_date, nav, source, source_url, fetched_at, payload)
        VALUES($1,$2,$3,$4,$5,$6,$7::jsonb) ON CONFLICT(code, nav_date, source) DO UPDATE SET nav=EXCLUDED.nav, source_url=EXCLUDED.source_url, fetched_at=EXCLUDED.fetched_at, payload=EXCLUDED.payload`,
      [code, row.navDate, row.nav, row.source, row.sourceUrl, row.fetchedAt, JSON.stringify(row)]);
    },
  };
}

function createNavService({ adapter, store, now = () => Date.now(), ttlMs = 86400000 }) {
  if (!adapter?.id || typeof adapter.fetchHistory !== 'function') throw new Error('Invalid nav adapter');
  const pending = new Map();
  return {
    async history(code, { refresh = false, limit = 100 } = {}) {
      validateCode(code);
      const cached = await store.history(code, limit);
      const latestAge = cached[0] ? now() - Date.parse(cached[0].fetched_at || cached[0].fetchedAt) : Infinity;
      if (!refresh && cached.length && latestAge >= 0 && latestAge < ttlMs) return { items: cached, stale: false };
      if (pending.has(code)) return pending.get(code);
      const task = (async () => {
        try {
          const rows = await adapter.fetchHistory(code);
          if (!rows.length) throw new Error('无正式净值');
          await store.write(code, rows);
          return { items: await store.history(code, limit), stale: false };
        } catch (error) {
          if (cached.length) return { items: cached, stale: true, refreshError: '净值刷新失败，正在使用历史缓存' };
          throw error;
        } finally { pending.delete(code); }
      })();
      pending.set(code, task);
      return task;
    },
    async latest(code, options) {
      const result = await this.history(code, options);
      return { ...result.items[0], stale: result.stale, refreshError: result.refreshError || null };
    },
  };
}

function installNavRoutes(app, service) {
  app.get('/api/funds/:code/nav', async (req, res) => {
    try { res.json(await service.latest(req.params.code, { refresh: req.query.refresh === '1' })); }
    catch { res.status(502).json({ error: '基金正式净值暂时不可用' }); }
  });
  app.get('/api/funds/:code/nav/history', async (req, res) => {
    try { res.json(await service.history(req.params.code, { refresh: req.query.refresh === '1' })); }
    catch { res.status(502).json({ error: '基金净值历史暂时不可用' }); }
  });
}

function configuredNavService(env = process.env) {
  const { Pool } = require('pg');
  const pool = new Pool({ ...(env.DATABASE_URL ? { connectionString: env.DATABASE_URL } : { host: env.POSTGRES_HOST || '127.0.0.1', port: Number(env.POSTGRES_PORT || 5432), database: env.POSTGRES_DB || 'positionassistant', user: env.POSTGRES_USER || 'positionassistant', password: env.POSTGRES_PASSWORD }), connectionTimeoutMillis: 5000, query_timeout: 10000 });
  return createNavService({ adapter: eastmoneyNavAdapter(), store: postgresStore(pool) });
}

module.exports = { validateCode, eastmoneyNavAdapter, postgresStore, createNavService, installNavRoutes, configuredNavService };
