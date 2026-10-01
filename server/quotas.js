function cleanHtml(value) { return String(value || '').replace(/<[^>]+>/g, '').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/\s+/g, ' ').trim(); }
function amountFromText(value) {
  const match = String(value || '').replace(/,/g, '').match(/([0-9]+(?:\.[0-9]+)?)(万|亿)?元/);
  if (!match) return null;
  const amount = Number(match[1]);
  return match[2] === '万' ? amount * 10000 : match[2] === '亿' ? amount * 100000000 : amount;
}
function classifyFund(name) {
  const value = String(name || '');
  if (/纳斯达克\s*100|纳指\s*100|NASDAQ\s*100/i.test(value)) return '纳斯达克100';
  if (/标普\s*500|S&P\s*500|SP500/i.test(value)) return '标普500';
  return null;
}
function isCandidate(fund) {
  return Boolean(classifyFund(fund?.name)) && /QDII|纳斯达克|标普|NASDAQ|S&P/i.test(fund.name) && !/美元|美钞|美汇/.test(fund.name);
}
function managerCode(fund = {}) {
  if (fund.managerCode) return String(fund.managerCode);
  const name = String(fund.name || '');
  if (/华夏/.test(name)) return 'china-asset';
  if (/南方/.test(name)) return 'southern';
  if (/易方达/.test(name)) return 'e-fund';
  if (/华宝/.test(name)) return 'fortis';
  if (/摩根/.test(name)) return 'jpmorgan';
  if (/广发/.test(name)) return 'guangfa';
  if (/国泰/.test(name)) return 'guotai';
  if (/招商/.test(name)) return 'cmbchina';
  if (/博时/.test(name)) return 'bosera';
  if (/建信/.test(name)) return 'ccbfund';
  if (/天弘/.test(name)) return 'tianhong';
  if (/汇添富/.test(name)) return 'fullgoal';
  if (/嘉实/.test(name)) return 'harvest';
  if (/大成/.test(name)) return 'dacheng';
  if (/华安/.test(name)) return 'huaan';
  if (/万家/.test(name)) return 'wanjia';
  if (/宝盈/.test(name)) return 'baoying';
  return null;
}
function normalizeChannel(channel = {}, fallback = {}) {
  const value = { ...channel };
  return {
    status: value.status == null ? '未知' : String(value.status),
    limit: value.limit == null ? null : Number(value.limit),
    limitType: value.limitType || 'per-account-daily',
    directPlatform: value.directPlatform || fallback.directPlatform || null,
    source: value.source || null,
    sourceType: value.sourceType || null,
    sourceUrl: value.sourceUrl || null,
    effectiveFrom: value.effectiveFrom || null,
    updatedAt: value.updatedAt || fallback.updatedAt || null,
    adapterId: value.adapterId || null,
    error: value.error || null
  };
}
function preferredChannel(channels = {}) {
  const direct = channels.direct;
  const distribution = channels.distribution;
  if (direct && (direct.status === '开放申购' || direct.status === '限大额')) return 'direct';
  if (distribution && (distribution.status === '开放申购' || distribution.status === '限大额')) return 'distribution';
  if (direct && direct.status !== '未知') return 'direct';
  if (distribution && distribution.status !== '未知') return 'distribution';
  return 'unknown';
}
function channelQuality(channels = {}) {
  const values = Object.values(channels).filter(Boolean);
  if (!values.length) return 'unknown';
  if (values.some(value => value.sourceType === 'fund-manager-page' || value.sourceType === 'fund-manager-announcement')) return 'verified';
  return values.some(value => value.sourceType === 'public') ? 'public' : 'unknown';
}
function normalizeQuota(item = {}) {
  const legacyDistribution = item.channels?.distribution || {
    status: item.status,
    limit: item.limit,
    source: item.source,
    sourceType: item.sourceType,
    sourceUrl: item.sourceUrl,
    updatedAt: item.updatedAt,
    adapterId: item.adapterId
  };
  const channels = {};
  if (legacyDistribution.status != null || legacyDistribution.limit != null || legacyDistribution.source != null) channels.distribution = normalizeChannel(legacyDistribution, item);
  if (item.channels?.direct) channels.direct = normalizeChannel(item.channels.direct, item);
  const preferred = item.preferredChannel && channels[item.preferredChannel] ? item.preferredChannel : preferredChannel(channels);
  const selected = channels[preferred] || channels.distribution || channels.direct || normalizeChannel({}, item);
  return { ...item, channels, preferredChannel: preferred, dataQuality: item.dataQuality || channelQuality(channels), status: selected.status, limit: selected.limit, source: selected.source, sourceType: selected.sourceType, sourceUrl: selected.sourceUrl, updatedAt: selected.updatedAt };
}
function withChannel(item, channel, data) {
  const normalized = normalizeQuota(item);
  const channels = { ...normalized.channels, [channel]: normalizeChannel(data, normalized) };
  return normalizeQuota({ ...normalized, channels, preferredChannel: preferredChannel(channels), dataQuality: channelQuality(channels) });
}
function channelOverrideFields(item) {
  const fields = Array.isArray(item?.overrideFields) ? item.overrideFields : [];
  if (fields.length) return fields;
  if (isUserOverride(item)) return ['status', 'limit'].filter(field => Object.prototype.hasOwnProperty.call(item, field));
  return [];
}
function getPath(object, path) { return path.split('.').reduce((value, key) => value == null ? undefined : value[key], object); }
function setPath(object, path, value) {
  const parts = path.split('.'); let target = object;
  for (const part of parts.slice(0, -1)) target = target[part] ||= {};
  target[parts[parts.length - 1]] = value;
}
function parseQuotaPage(html, fund, supplemental = {}) {
  const statusMatch = String(html).match(/交易状态：[\s\S]{0,220}?class="staticCell">\s*([^<]+)/);
  const status = statusMatch ? cleanHtml(statusMatch[1]).replace(/[（(].*$/, '').trim() : '未知';
  const limitMatch = String(html).match(/单日累计购买上限\s*([0-9]+(?:\.[0-9]+)?)\s*(万|亿)?元/);
  const parsed = limitMatch ? amountFromText(`${limitMatch[1]}${limitMatch[2] || ''}元`) : null;
  const extra = supplemental[fund.code];
  const limit = parsed == null && extra ? extra.limit : parsed;
  const clean = cleanHtml(html);
  const rateMatch = clean.match(/近一年(?:收益率|收益)[：:\s]*([+-]?[0-9]+(?:\.[0-9]+)?)\s*%/);
  const detailMatch = clean.match(/(?:申购说明|详情说明|基金概况)[：:\s]*([^。；]{2,120})/);
  const source = parsed == null && extra ? extra : { source: '东方财富基金详情页', sourceType: 'public', sourceUrl: `https://fund.eastmoney.com/${fund.code}.html` };
  return normalizeQuota({ code: fund.code, name: fund.name, category: classifyFund(fund.name), status, limit,
    annualReturn: rateMatch ? Number(rateMatch[1]) / 100 : (extra?.annualReturn ?? null),
    detail: detailMatch ? detailMatch[1].trim() : (extra?.detail || null),
    source: source.source, sourceType: source.sourceType, sourceUrl: source.sourceUrl,
    updatedAt: new Date().toISOString(), adapterId: 'eastmoney-distribution-v2',
    channels: { distribution: { status, limit, source: source.source, sourceType: source.sourceType, sourceUrl: source.sourceUrl, updatedAt: new Date().toISOString(), adapterId: 'eastmoney-distribution-v2' } }
  });
}function isUserOverride(item) { return Boolean(item?.userOverride && item.userId); }
function overrideFields(item) { return channelOverrideFields(item); }
function quotaPriority(item) { return isUserOverride(item) ? 'user' : 'automatic'; }
function applyOverrideChannels(base, override, fields) {
  const channels = JSON.parse(JSON.stringify(base?.channels || override?.channels || {}));
  if (!channels.distribution && (override?.status != null || override?.limit != null)) channels.distribution = normalizeChannel({}, base || override || {});
  for (const field of fields) {
    if (field === 'status' || field === 'limit') {
      channels.distribution ||= normalizeChannel({}, base || override || {});
      if (Object.prototype.hasOwnProperty.call(override, field)) channels.distribution[field] = override[field];
    } else if (field.startsWith('channels.')) {
      const parts = field.split('.').slice(1); let target = channels;
      for (const part of parts.slice(0, -1)) target = target[part] ||= {};
      target[parts[parts.length - 1]] = getPath(override, field);
    }
  }
  return channels;
}function visibleQuotas(records = [], ownerId = null) {
  const automatic = new Map(); const overrides = new Map();
  for (const raw of records || []) {
    const item = normalizeQuota(raw);
    if (isUserOverride(item)) { if (item.userId === ownerId) overrides.set(item.code, item); }
    else if (item?.code) automatic.set(item.code, item);
  }
  const codes = new Set([...automatic.keys(), ...overrides.keys()]);
  return [...codes].map(code => {
    const base = automatic.get(code); const override = overrides.get(code);
    if (!override) return { ...base, userOverride: false, valueSource: 'automatic', priority: 'automatic', overrideFields: [] };
    const fields = overrideFields(override);
    const result = { ...(base || {}), ...override, channels: applyOverrideChannels(base, override, fields), userOverride: true, valueSource: 'user', priority: 'user', overrideFields: fields };
    const normalized = normalizeQuota(result);
    if (base) {
      normalized.automaticStatus = base.status ?? null;
      normalized.automaticLimit = base.limit ?? null;
      normalized.automaticChannels = base.channels;
      for (const channelName of Object.keys(normalized.channels || {})) {
        const overrideChannel = getPath(override, `channels.${channelName}`);
        const baseChannel = getPath(base, `channels.${channelName}`);
        if (!overrideChannel || !baseChannel) continue;
        if (!fields.includes(`channels.${channelName}.status`) && !fields.includes('status')) normalized.channels[channelName].status = baseChannel.status;
        if (!fields.includes(`channels.${channelName}.limit`) && !fields.includes('limit')) normalized.channels[channelName].limit = baseChannel.limit;
      }
      const selected = normalized.channels[normalized.preferredChannel] || {};
      normalized.status = fields.includes('status') ? (override.status ?? selected.status) : (base.status ?? selected.status);
      normalized.limit = fields.includes('limit') ? (override.limit ?? selected.limit) : (base.limit ?? selected.limit);
    }
    delete normalized.userId;
    normalized.userOverride = true;
    return normalized;
  });
}
function mergeAutomaticQuotas(fresh, old = []) {
  const oldOverrides = new Map();
  for (const raw of old || []) {
    const item = normalizeQuota(raw);
    if (isUserOverride(item)) { if (!oldOverrides.has(item.code)) oldOverrides.set(item.code, []); oldOverrides.get(item.code).push(item); }
  }
  const merged = [];
  for (const raw of fresh) {
    const item = normalizeQuota(raw);
    for (const current of oldOverrides.get(item.code) || []) {
      const fields = overrideFields(current);
      merged.push({ ...item, ...current, channels: applyOverrideChannels(item, current, fields), userOverride: true, userId: current.userId,
        overrideFields: fields, valueSource: 'user', priority: 'user', automaticChannels: item.channels, automaticStatus: item.status, automaticLimit: item.limit });
    }
    merged.push({ ...item, userOverride: false, valueSource: 'automatic', priority: 'automatic', overrideFields: [] });
  }
  return merged.map(normalizeQuota);
}function restoreAutomaticQuota(records = [], fresh, ownerId) {
  if (!fresh?.code) return records || [];
  const matching = (records || []).filter(item => item?.code === fresh.code);
  const rebuilt = mergeAutomaticQuotas([fresh], matching).filter(item => !(isUserOverride(item) && item.userId === ownerId));
  return (records || []).filter(item => item?.code !== fresh.code).concat(rebuilt);
}
module.exports = { amountFromText, classifyFund, isCandidate, managerCode, normalizeChannel, normalizeQuota, withChannel, preferredChannel, channelQuality, parseQuotaPage, mergeAutomaticQuotas, restoreAutomaticQuota, isUserOverride, overrideFields, quotaPriority, visibleQuotas, getPath, setPath };













