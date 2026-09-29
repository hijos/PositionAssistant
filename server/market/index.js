const CHART_URL = 'https://query1.finance.yahoo.com/v8/finance/chart/';

// 第一版估算链路跟踪的默认行情代码：纳斯达克100、标普500 与 USD/CNY 汇率。
const TRACKED_SYMBOLS = Object.freeze({ nasdaq100: '^NDX', sp500: '^GSPC', usdCny: 'CNY=X' });
const TRACKED_SYMBOL_SET = new Set(Object.values(TRACKED_SYMBOLS));

function validateSymbol(symbol) {
  if (typeof symbol !== 'string' || !/^[A-Za-z0-9.^=-]{1,20}$/.test(symbol)) {
    const error = new Error('行情代码无效');
    error.code = 'INVALID_MARKET_SYMBOL';
    throw error;
  }
  return symbol;
}

function validateTrackedSymbol(symbol) {
  validateSymbol(symbol);
  if (!TRACKED_SYMBOL_SET.has(symbol)) {
    const error = new Error('行情代码不受支持');
    error.code = 'UNSUPPORTED_MARKET_SYMBOL';
    throw error;
  }
  return symbol;
}

function normalizeChart(body, symbol, source, sourceUrl, fetchedAt) {
  const result = body?.chart?.result?.[0];
  if (!result || body?.chart?.error) throw new Error('行情响应无效');
  const timezone = typeof result.meta?.exchangeTimezoneName === 'string' ? result.meta.exchangeTimezoneName : 'UTC';
  const timestamps = result.timestamp;
  const closes = result.indicators?.quote?.[0]?.close;
  if (!Array.isArray(timestamps) || !Array.isArray(closes)) throw new Error('行情响应无效');
  const seen = new Set();
  const rows = [];
  for (let i = 0; i < timestamps.length; i++) {
    const price = Number(closes[i]);
    const at = Number(timestamps[i]);
    if (!Number.isFinite(price) || price <= 0 || !Number.isFinite(at)) continue;
    const date = new Date(at * 1000).toLocaleDateString('en-CA', { timeZone: timezone });
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || seen.has(date)) continue;
    seen.add(date);
    rows.push({ symbol, date, price, source, sourceUrl, fetchedAt });
  }
  if (!rows.length) throw new Error('行情响应无有效记录');
  return rows.sort((a, b) => b.date.localeCompare(a.date));
}

function yahooMarketAdapter(fetchImpl = fetch) {
  return {
    id: 'yahoo-chart-v1', sourceUrl: CHART_URL,
    async fetchHistory(symbol, { days = 40 } = {}) {
      validateSymbol(symbol);
      const period2 = Math.floor(Date.now() / 1000) + 86400;
      const period1 = period2 - Math.max(1, Math.min(Number(days) || 40, 400)) * 86400;
      const url = `${CHART_URL}${encodeURIComponent(symbol)}?interval=1d&period1=${period1}&period2=${period2}`;
      const response = await fetchImpl(url, { headers: { 'User-Agent': 'Mozilla/5.0' }, signal: AbortSignal.timeout(10000) });
      if (!response.ok) throw new Error(`行情接口 ${response.status}`);
      const body = await response.json();
      return normalizeChart(body, symbol, this.id, this.sourceUrl, new Date().toISOString());
    },
  };
}

function postgresStore(pool) {
  const mapRow = row => ({ symbol: row.symbol, date: String(row.trade_date).slice(0, 10), price: Number(row.price), source: row.source, sourceUrl: row.source_url, fetchedAt: new Date(row.fetched_at).toISOString() });
  return {
    async latest(symbol, source) {
      const r = await pool.query('SELECT symbol, trade_date, price, source, source_url, fetched_at FROM positionassistant.market_snapshots WHERE symbol=$1 AND source=$2 ORDER BY trade_date DESC, fetched_at DESC LIMIT 1', [symbol, source]);
      return r.rows[0] ? mapRow(r.rows[0]) : null;
    },
    async history(symbol, limit = 60, source) {
      const r = await pool.query('SELECT symbol, trade_date, price, source, source_url, fetched_at FROM positionassistant.market_snapshots WHERE symbol=$1 AND source=$2 ORDER BY trade_date DESC LIMIT $3', [symbol, source, limit]);
      return r.rows.map(mapRow);
    },
    async write(symbol, rows, source) {
      for (const row of rows) {
        if (row.source !== source) throw new Error('行情来源无效');
        await pool.query(`INSERT INTO positionassistant.market_snapshots(symbol, trade_date, price, source, source_url, fetched_at, payload)
        VALUES($1,$2,$3,$4,$5,$6,$7::jsonb) ON CONFLICT(symbol, trade_date, source) DO UPDATE SET price=EXCLUDED.price, source_url=EXCLUDED.source_url, fetched_at=EXCLUDED.fetched_at, payload=EXCLUDED.payload`,
        [symbol, row.date, row.price, row.source, row.sourceUrl, row.fetchedAt, JSON.stringify(row)]);
      }
    },
  };
}

function createMarketService({ adapter, store, now = () => Date.now(), ttlMs = 900000 }) {
  if (!adapter?.id || typeof adapter.fetchHistory !== 'function') throw new Error('Invalid market adapter');
  const pending = new Map();
  return {
    async history(symbol, { refresh = false, limit = 60 } = {}) {
      validateSymbol(symbol);
      const cached = await store.history(symbol, limit, adapter.id);
      const latestAge = cached[0] ? now() - Date.parse(cached[0].fetched_at || cached[0].fetchedAt) : Infinity;
      if (!refresh && cached.length && latestAge >= 0 && latestAge < ttlMs) return { items: cached, stale: false };
      if (pending.has(symbol)) return pending.get(symbol);
      const task = (async () => {
        try {
          const rows = await adapter.fetchHistory(symbol);
          if (!rows.length || rows.some(row => row?.source !== adapter.id)) throw new Error('行情记录无效');
          await store.write(symbol, rows, adapter.id);
          return { items: await store.history(symbol, limit, adapter.id), stale: false };
        } catch (error) {
          if (cached.length) return { items: cached, stale: true, refreshError: '行情刷新失败，正在使用历史缓存' };
          throw error;
        } finally { pending.delete(symbol); }
      })();
      pending.set(symbol, task);
      return task;
    },
    async quote(symbol, options) {
      const result = await this.history(symbol, { ...options, limit: 1 });
      return { ...result.items[0], stale: result.stale, refreshError: result.refreshError || null };
    },
  };
}

function installMarketRoutes(app, service) {
  app.get('/api/market/:symbol/quote', async (req, res) => {
    try {
      validateTrackedSymbol(req.params.symbol);
      res.json(await service.quote(req.params.symbol, { refresh: req.query.refresh === '1' }));
    } catch (error) {
      res.status(error?.code === 'INVALID_MARKET_SYMBOL' || error?.code === 'UNSUPPORTED_MARKET_SYMBOL' ? 400 : 502)
        .json({ error: error?.code === 'UNSUPPORTED_MARKET_SYMBOL' ? '行情代码不受支持' : '指数行情或汇率暂时不可用' });
    }
  });
  app.get('/api/market/:symbol/history', async (req, res) => {
    try {
      validateTrackedSymbol(req.params.symbol);
      res.json(await service.history(req.params.symbol, { refresh: req.query.refresh === '1' }));
    } catch (error) {
      res.status(error?.code === 'INVALID_MARKET_SYMBOL' || error?.code === 'UNSUPPORTED_MARKET_SYMBOL' ? 400 : 502)
        .json({ error: error?.code === 'UNSUPPORTED_MARKET_SYMBOL' ? '行情代码不受支持' : '指数行情历史暂时不可用' });
    }
  });
}

function configuredMarketService(env = process.env) {
  const { Pool } = require('pg');
  const pool = new Pool({ ...(env.DATABASE_URL ? { connectionString: env.DATABASE_URL } : { host: env.POSTGRES_HOST || '127.0.0.1', port: Number(env.POSTGRES_PORT || 5432), database: env.POSTGRES_DB || 'positionassistant', user: env.POSTGRES_USER || 'positionassistant', password: env.POSTGRES_PASSWORD }), connectionTimeoutMillis: 5000, query_timeout: 10000 });
  return createMarketService({ adapter: yahooMarketAdapter(), store: postgresStore(pool) });
}

module.exports = { TRACKED_SYMBOLS, validateSymbol, validateTrackedSymbol, normalizeChart, yahooMarketAdapter, postgresStore, createMarketService, installMarketRoutes, configuredMarketService };
