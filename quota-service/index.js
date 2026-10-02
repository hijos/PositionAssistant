const express = require('express');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const STATUSES = new Set(['开放申购', '暂停申购', '限大额', '未知']);
const CHANNELS = new Set(['distribution', 'direct']);
const DEFAULT_SETTINGS = { minSupport: 3, agreementRatio: 0.8, windowHours: 72 };
const FUND_CATALOG = JSON.parse(fs.readFileSync(path.join(__dirname, 'fund-catalog.json'), 'utf8'));

function fundFamilyKey(item) {
  return String(item.name || '')
    .replace(/\(人民币\)/g, '')
    .replace(/人民币/g, '')
    .replace(/[ACDEFI]$/, '');
}

function fundShareClass(item) {
  const normalized = String(item.name || '').replace(/\(人民币\)/g, '').replace(/人民币/g, '');
  const match = normalized.match(/([ACDEFI])$/);
  return match ? { A: 0, C: 1, D: 2, E: 3, F: 4, I: 5 }[match[1]] : 9;
}

function compareFunds(a, b) {
  return String(a.category).localeCompare(String(b.category), 'zh-CN')
    || fundFamilyKey(a).localeCompare(fundFamilyKey(b), 'zh-CN')
    || fundShareClass(a) - fundShareClass(b)
    || String(a.code).localeCompare(String(b.code));
}

function isSearchableCatalogFund(item) {
  const name = String(item.name || '').normalize('NFKC').toUpperCase();
  // Direct exchange-traded ETFs are not OTC quota products. ETF联接/连接
  // funds remain searchable, including names with “发起式” between ETF and 联接.
  return !/ETF/.test(name) || /ETF[^\n]{0,24}(联接|连接)/.test(name);
}

// Keep the admin autocomplete source safe to use even if the seed file is
// edited by hand: a duplicate code would make the UI choose an arbitrary
// name, and a malformed code cannot be a valid fund identifier.
if (!Array.isArray(FUND_CATALOG) || FUND_CATALOG.some(item => !item || !/^\d{6}$/.test(String(item.code)) || !String(item.name || '').trim())) {
  throw new Error('quota-service fund catalog contains an invalid entry');
}
if (new Set(FUND_CATALOG.map(item => String(item.code))).size !== FUND_CATALOG.length) {
  throw new Error('quota-service fund catalog contains duplicate codes');
}
FUND_CATALOG.splice(0, FUND_CATALOG.length, ...FUND_CATALOG.filter(isSearchableCatalogFund));
FUND_CATALOG.sort(compareFunds);

function clone(value) { return value == null ? value : JSON.parse(JSON.stringify(value)); }
function timestamp(clock) { return clock().toISOString(); }
function validCode(code) { return /^\d{6}$/.test(String(code || '')); }
function normalizeStatus(value) {
  const text = String(value == null ? '未知' : value).trim();
  if (!STATUSES.has(text)) throw new Error('申购状态无效');
  return text;
}
function normalizeLimit(value) {
  if (value == null || String(value).trim() === '') return null;
  const number = Number(String(value).replace(/,/g, '').trim());
  if (!Number.isFinite(number) || number < 0) throw new Error('limit must be a non-negative number or null');
  return Math.round((number + Number.EPSILON) * 100) / 100;
}
function normalizeFeeRate(value) {
  if (value == null || String(value).trim() === '') return null;
  const number = Number(value);
  if (!Number.isFinite(number) || number < 0 || number > 1) throw new Error('feeRate must be between 0 and 1');
  return Math.round((number + Number.EPSILON) * 1000000) / 1000000;
}
function normalizeChannel(raw = {}) {
  return {
    ...raw,
    status: normalizeStatus(raw.status),
    limit: normalizeLimit(raw.limit),
    limitType: raw.limitType || 'per-account-daily',
    directPlatform: raw.directPlatform || null,
    source: raw.source || '管理员录入',
    sourceType: raw.sourceType || 'manual',
    sourceUrl: raw.sourceUrl || null,
    effectiveFrom: raw.effectiveFrom || null,
    updatedAt: raw.updatedAt || null,
    error: raw.error || null,
  };
}
function normalizeQuota(raw = {}) {
  const legacy = raw.channels ? null : {
    status: raw.status, limit: raw.limit, source: raw.source,
    sourceType: raw.sourceType, sourceUrl: raw.sourceUrl, updatedAt: raw.updatedAt,
  };
  const source = raw.channels || {};
  const legacyFeeRate = raw.feeRate ?? source.distribution?.feeRate ?? source.direct?.feeRate;
  const channels = {};
  if (source.distribution || legacy) channels.distribution = normalizeChannel(source.distribution || legacy);
  if (source.direct) channels.direct = normalizeChannel(source.direct);
  return {
    ...raw,
    code: String(raw.code || ''),
    name: String(raw.name || raw.code || ''),
    category: String(raw.category || 'QDII'),
    annualReturn: raw.annualReturn == null ? null : Number(raw.annualReturn),
    feeRate: legacyFeeRate == null ? null : normalizeFeeRate(legacyFeeRate),
    detail: raw.detail || null,
    channels,
    revision: Number.isInteger(raw.revision) ? raw.revision : 0,
    updatedAt: raw.updatedAt || null,
    source: raw.source || '管理员录入',
    sourceType: raw.sourceType || 'manual',
  };
}
function emptyDb() { return { schemaVersion: 1, version: 0, settings: { ...DEFAULT_SETTINGS }, quotas: [], corrections: [], audit: [] }; }
function saveDb(file, db) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(temp, JSON.stringify(db, null, 2), 'utf8');
  fs.renameSync(temp, file);
}
function loadDb(file) {
  try {
    const parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
    return {
      ...emptyDb(), ...parsed,
      settings: { ...DEFAULT_SETTINGS, ...(parsed.settings || {}) },
      quotas: Array.isArray(parsed.quotas) ? parsed.quotas.map(normalizeQuota) : [],
      corrections: Array.isArray(parsed.corrections) ? parsed.corrections : [],
      audit: Array.isArray(parsed.audit) ? parsed.audit : [],
    };
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
    const db = emptyDb();
    saveDb(file, db);
    return db;
  }
}
function id(prefix) { return `${prefix}_${crypto.randomBytes(10).toString('hex')}`; }
function hash(value, salt) { return crypto.createHash('sha256').update(`${salt}:${value}`).digest('hex').slice(0, 24); }
function candidateKey(fields) { return JSON.stringify({ status: fields.status, limit: fields.limit }); }
function currentQuota(db, code) { return db.quotas.find(item => item.code === code) || null; }
function clientIp(req, trustProxy) {
  if (trustProxy) {
    const forwarded = String(req.headers['x-forwarded-for'] || '').split(',')[0].trim();
    if (forwarded) return forwarded;
  }
  return req.socket.remoteAddress || 'unknown';
}
function correctionFields(body) { return { status: normalizeStatus(body.status), limit: normalizeLimit(body.limit) }; }
function bump(db, item, at) { db.version += 1; item.revision = db.version; item.updatedAt = at; }

function summaryFor(db, code, channel, clock) {
  const item = currentQuota(db, code);
  if (!item || !CHANNELS.has(channel)) return null;
  const cutoff = clock().getTime() - db.settings.windowHours * 3600000;
  const active = db.corrections.filter(record => record.status === 'active' && record.code === code && record.channel === channel && record.baseRevision === item.revision && Date.parse(record.createdAt) >= cutoff);
  const groups = new Map();
  for (const record of active) {
    const group = groups.get(record.candidateKey) || { candidateKey: record.candidateKey, fields: record.fields, voters: new Set(), correctionIds: [] };
    group.voters.add(record.voterHash);
    group.correctionIds.push(record.id);
    groups.set(record.candidateKey, group);
  }
  const total = new Set(active.map(record => record.voterHash)).size;
  const candidates = [...groups.values()].map(group => ({
    candidateKey: group.candidateKey,
    fields: group.fields,
    support: group.voters.size,
    total,
    ratio: total ? group.voters.size / total : 0,
    correctionIds: group.correctionIds,
  })).sort((a, b) => b.support - a.support || b.ratio - a.ratio);
  const winner = candidates[0] || null;
  return {
    code, channel, baseRevision: item.revision, total, candidates, winner,
    ready: Boolean(winner && winner.support >= db.settings.minSupport && winner.ratio >= db.settings.agreementRatio),
    settings: { ...db.settings },
  };
}

function applyConsensus(db, summary, clock) {
  if (!summary?.ready || !summary.winner) return null;
  const item = currentQuota(db, summary.code);
  if (!item || item.revision !== summary.baseRevision) return null;
  const at = timestamp(clock);
  const before = clone(item);
  item.channels[summary.channel] = {
    ...(item.channels[summary.channel] || normalizeChannel({})),
    ...summary.winner.fields,
    source: '用户共识纠错', sourceType: 'user-consensus', updatedAt: at,
  };
  item.source = '用户共识纠错';
  item.sourceType = 'user-consensus';
  item.consensus = { support: summary.winner.support, total: summary.total, ratio: summary.winner.ratio, appliedAt: at };
  bump(db, item, at);
  const audit = {
    id: id('audit'), type: 'consensus-applied', code: item.code, channel: summary.channel,
    before, after: clone(item), afterRevision: item.revision,
    correctionIds: summary.winner.correctionIds, rule: { ...db.settings }, createdAt: at,
  };
  db.audit.unshift(audit);
  for (const record of db.corrections) {
    if (summary.winner.correctionIds.includes(record.id)) {
      record.status = 'applied'; record.appliedAt = at; record.appliedRevision = item.revision; record.auditId = audit.id;
    }
  }
  return audit;
}

function adminToken(req) {
  const match = String(req.headers.authorization || '').match(/^Bearer\s+(.+)$/i);
  return match ? match[1].trim() : String(req.headers['x-admin-token'] || '').trim();
}

function createQuotaServiceApp(options = {}) {
  const dbPath = options.dbPath || process.env.QUOTA_DB_PATH || path.join(__dirname, 'data', 'db.json');
  const adminPassword = options.adminPassword || process.env.QUOTA_ADMIN_PASSWORD;
  if (!adminPassword || adminPassword.length < 8) throw new Error('QUOTA_ADMIN_PASSWORD must be at least 8 characters');
  const trustProxy = options.trustProxy ?? process.env.QUOTA_TRUST_PROXY === '1';
  const ipSalt = options.ipSalt || process.env.QUOTA_IP_HASH_SALT || 'quota-service-dev-salt';
  const clock = options.now || (() => new Date());
  const db = loadDb(dbPath);
  const sessions = new Map();
  const app = express();

  app.use(express.json({ limit: '128kb' }));
  app.use((req, res, next) => {
    const origin = process.env.QUOTA_CORS_ORIGIN || '*';
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Client-Id, X-Idempotency-Key');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, OPTIONS');
    if (req.method === 'OPTIONS') return res.sendStatus(204);
    next();
  });
  function requireAdmin(req, res, next) {
    const token = adminToken(req);
    const session = sessions.get(token);
    if (!session || session.expiresAt < Date.now()) return res.status(401).json({ error: '需要管理员登录' });
    next();
  }

  app.get('/health', (req, res) => res.json({ ok: true, service: 'quota-service', version: db.version }));
  const loginAttempts = new Map();
  app.post('/api/admin/login', (req, res) => {
    const ip = clientIp(req, trustProxy);
    const previous = loginAttempts.get(ip) || { count: 0, until: 0 };
    if (previous.count >= 10 && previous.until > Date.now()) return res.status(429).json({ error: '登录尝试过多，请稍后重试' });
    if (previous.until <= Date.now()) previous.count = 0;
    previous.until = Date.now() + 15 * 60 * 1000;
    previous.count += 1;
    loginAttempts.set(ip, previous);
    if (String(req.body?.password || '') !== adminPassword) return res.status(401).json({ error: '管理员密码错误' });
    loginAttempts.delete(ip);
    const token = crypto.randomBytes(32).toString('base64url');
    sessions.set(token, { expiresAt: Date.now() + 7 * 24 * 3600000 });
    res.json({ token, expiresIn: 7 * 24 * 3600 });
  });
  app.post('/api/admin/logout', requireAdmin, (req, res) => { sessions.delete(adminToken(req)); res.sendStatus(204); });

  app.get('/api/quotas', (req, res) => res.json({
    version: db.version,
    updatedAt: db.quotas.reduce((latest, item) => !latest || item.updatedAt > latest ? item.updatedAt : latest, null),
    items: db.quotas.map(clone),
  }));
  app.get('/api/quotas/:code', (req, res) => {
    const item = currentQuota(db, req.params.code);
    if (!item) return res.sendStatus(404);
    res.json({ version: db.version, item: clone(item) });
  });

  app.post('/api/corrections', (req, res) => {
    const code = String(req.body?.code || '');
    const channel = String(req.body?.channel || '');
    if (!validCode(code) || !CHANNELS.has(channel)) return res.status(400).json({ error: 'code or channel is invalid' });
    const item = currentQuota(db, code);
    if (!item) return res.status(404).json({ error: '额度记录不存在' });
    if (req.body?.baseRevision != null && req.body.baseRevision !== item.revision) return res.status(409).json({ error: '云端额度已更新，请刷新后重试' });
    let fields;
    try { fields = correctionFields(req.body || {}); } catch (error) { return res.status(400).json({ error: error.message }); }
    const voterHash = hash(clientIp(req, trustProxy), ipSalt);
    const clientId = String(req.headers['x-client-id'] || req.body?.clientId || '').trim().slice(0, 128) || null;
    const idempotencyKey = String(req.headers['x-idempotency-key'] || req.body?.idempotencyKey || '').trim().slice(0, 160) || null;
    if (idempotencyKey) {
      const previous = db.corrections.find(record => record.idempotencyKey === idempotencyKey && record.voterHash === voterHash);
      if (previous) {
        if (previous.code !== code || previous.channel !== channel || previous.candidateKey !== candidateKey(fields)) return res.status(409).json({ error: '重复请求标识对应不同内容' });
        return res.json({ accepted: true, duplicate: true, id: previous.id, status: previous.status, version: db.version, summary: summaryFor(db, code, channel, clock) });
      }
    }
    for (const record of db.corrections) {
      if (record.status === 'active' && record.code === code && record.channel === channel && record.voterHash === voterHash) record.status = 'superseded';
    }
    const at = timestamp(clock);
    const record = {
      id: id('correction'), code, channel, fields, candidateKey: candidateKey(fields),
      baseRevision: item.revision, voterHash, clientId, idempotencyKey, createdAt: at, status: 'active',
    };
    db.corrections.unshift(record);
    const summary = summaryFor(db, code, channel, clock);
    const audit = applyConsensus(db, summary, clock);
    saveDb(dbPath, db);
    res.status(201).json({ accepted: true, id: record.id, status: audit ? 'applied' : 'pending', version: db.version, summary: summaryFor(db, code, channel, clock), appliedAuditId: audit?.id || null });
  });

  app.get('/api/admin/quotas', requireAdmin, (req, res) => res.json({ version: db.version, items: db.quotas.map(clone) }));
  app.get('/api/admin/fund-catalog', requireAdmin, (req, res) => res.json({ items: clone(FUND_CATALOG) }));
  app.put('/api/admin/quotas/:code', requireAdmin, (req, res) => {
    const code = String(req.params.code || '');
    const body = req.body || {};
    const has = (target, key) => Object.prototype.hasOwnProperty.call(target || {}, key);
    if (!validCode(code)) return res.status(400).json({ error: '基金代码无效' });
    let entries;
    if (body.channels != null) {
      if (typeof body.channels !== 'object' || Array.isArray(body.channels)) return res.status(400).json({ error: 'channels 格式无效' });
      entries = Object.entries(body.channels);
      if (!entries.length || entries.some(([key]) => !CHANNELS.has(key))) return res.status(400).json({ error: 'channel must be distribution or direct' });
    } else {
      const channel = String(body.channel || 'distribution');
      if (!CHANNELS.has(channel)) return res.status(400).json({ error: 'channel must be distribution or direct' });
      entries = [[channel, body]];
    }
    let nextFeeRate;
    const prepared = [];
    try {
      for (const [key, payload] of entries) {
        const update = {};
        if (has(payload, 'status')) update.status = normalizeStatus(payload.status);
        if (has(payload, 'limit')) update.limit = normalizeLimit(payload.limit);
        if (has(payload, 'sourceUrl')) update.sourceUrl = String(payload.sourceUrl || '').trim() || null;
        prepared.push([key, update]);
      }
      if (has(body, 'feeRatePercent')) {
        const percent = body.feeRatePercent == null || String(body.feeRatePercent).trim() === '' ? null : Number(body.feeRatePercent);
        if (percent != null && (!Number.isFinite(percent) || percent < 0 || percent > 100)) throw new Error('费率应在 0% 至 100% 之间');
        nextFeeRate = percent == null ? null : normalizeFeeRate(percent / 100);
      }
    } catch (error) { return res.status(400).json({ error: error.message }); }
    let item = currentQuota(db, code);
    const at = timestamp(clock);
    if (!item) {
      item = normalizeQuota({ code, name: body.name || code, category: body.category || 'QDII', channels: {} });
      db.quotas.push(item);
    }
    const before = clone(item);
    if (has(body, 'name')) item.name = String(body.name || code).trim().slice(0, 200) || code;
    if (has(body, 'category')) item.category = String(body.category || 'QDII').trim().slice(0, 40) || 'QDII';
    if (has(body, 'detail')) item.detail = String(body.detail || '').trim().slice(0, 500) || null;
    for (const [key, update] of prepared) {
      const next = { ...(item.channels[key] || normalizeChannel({})) };
      if (update.status !== undefined) next.status = update.status;
      if (next.status === '开放申购') next.limit = null;
      else if (update.limit !== undefined) next.limit = update.limit;
      if (update.sourceUrl !== undefined) next.sourceUrl = update.sourceUrl;
      next.source = '管理员录入'; next.sourceType = 'manual'; next.updatedAt = at;
      item.channels[key] = normalizeChannel(next);
    }
    if (has(body, 'feeRatePercent')) item.feeRate = nextFeeRate;
    item.source = '管理员录入'; item.sourceType = 'manual';
    bump(db, item, at);
    const updatedChannels = prepared.map(([key]) => key);
    db.audit.unshift({ id: id('audit'), type: 'manual-update', code, channel: updatedChannels.length === 1 ? updatedChannels[0] : null, channels: updatedChannels, before, after: clone(item), afterRevision: item.revision, createdAt: at });
    saveDb(dbPath, db);
    res.json({ version: db.version, item: clone(item) });
  });

  app.get('/api/admin/settings', requireAdmin, (req, res) => res.json({ ...db.settings }));
  app.put('/api/admin/settings', requireAdmin, (req, res) => {
    const minSupport = Number(req.body?.minSupport);
    const agreementRatio = Number(req.body?.agreementRatio);
    const windowHours = Number(req.body?.windowHours);
    if (!Number.isInteger(minSupport) || minSupport < 1 || minSupport > 1000 || !Number.isFinite(agreementRatio) || agreementRatio < 0.5 || agreementRatio > 1 || !Number.isFinite(windowHours) || windowHours < 1 || windowHours > 720) return res.status(400).json({ error: '纠错门槛无效' });
    db.settings = { minSupport, agreementRatio, windowHours };
    saveDb(dbPath, db);
    res.json({ ...db.settings });
  });
  app.get('/api/admin/corrections', requireAdmin, (req, res) => res.json({
    settings: { ...db.settings },
    items: db.corrections.map(record => ({ ...clone(record), voterHash: undefined, summary: summaryFor(db, record.code, record.channel, clock) })),
  }));
  app.get('/api/admin/audit', requireAdmin, (req, res) => res.json({ items: db.audit.map(clone) }));
  app.post('/api/admin/corrections/:id/revoke', requireAdmin, (req, res) => {
    const applied = db.audit.find(entry => entry.id === req.params.id && entry.type === 'consensus-applied');
    if (!applied) return res.status(404).json({ error: '共识更新记录不存在' });
    const item = currentQuota(db, applied.code);
    if (!item || item.revision !== applied.afterRevision) return res.status(409).json({ error: '该记录之后已有新的数据更新，不能直接撤销' });
    const at = timestamp(clock);
    const before = clone(item);
    Object.assign(item, clone(applied.before));
    item.source = '管理员撤销用户共识'; item.sourceType = 'admin-revocation';
    bump(db, item, at);
    const revocation = { id: id('audit'), type: 'consensus-revoked', code: item.code, channel: applied.channel, before, after: clone(item), afterRevision: item.revision, revertedAuditId: applied.id, reason: String(req.body?.reason || '').trim().slice(0, 200) || null, createdAt: at };
    db.audit.unshift(revocation);
    for (const record of db.corrections) if (record.auditId === applied.id) { record.status = 'revoked'; record.revokedAt = at; record.revocationAuditId = revocation.id; }
    saveDb(dbPath, db);
    res.json({ version: db.version, item: clone(item), audit: revocation });
  });

  app.use(express.static(path.join(__dirname, 'public')));
  return { app, db, dbPath };
}

if (require.main === module) {
  const host = process.env.QUOTA_HOST || '0.0.0.0';
  const port = Number(process.env.QUOTA_PORT || 4100);
  const { app } = createQuotaServiceApp();
  app.listen(port, host, () => console.log(`Quota service listening on http://${host}:${port}`));
}

module.exports = { createQuotaServiceApp, normalizeQuota, normalizeChannel, summaryFor, applyConsensus };
