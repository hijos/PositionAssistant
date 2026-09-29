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
  return { code: fund.code, name: fund.name, category: classifyFund(fund.name), status, limit,
    annualReturn: rateMatch ? Number(rateMatch[1]) / 100 : (extra?.annualReturn ?? null),
    detail: detailMatch ? detailMatch[1].trim() : (extra?.detail || null),
    source: parsed == null && extra ? extra.source : '东方财富基金详情页',
    sourceType: parsed == null && extra ? extra.sourceType : 'public', updatedAt: new Date().toISOString().slice(0, 10),
    sourceUrl: parsed == null && extra ? extra.sourceUrl : `https://fund.eastmoney.com/${fund.code}.html` };
}
function isUserOverride(item) {
  return Boolean(item?.userOverride && item.userId);
}

function overrideFields(item) {
  if (Array.isArray(item?.overrideFields) && item.overrideFields.length) return item.overrideFields;
  return isUserOverride(item) ? ['status', 'limit'] : [];
}

function quotaPriority(item) {
  return isUserOverride(item) ? 'user' : 'automatic';
}

function visibleQuotas(records = [], ownerId = null) {
  const automatic = new Map();
  const overrides = new Map();
  for (const item of records || []) {
    if (isUserOverride(item)) {
      if (item.userId === ownerId) overrides.set(item.code, item);
    } else if (item?.code) {
      automatic.set(item.code, item);
    }
  }
  const codes = new Set([...automatic.keys(), ...overrides.keys()]);
  return [...codes].map(code => {
    const base = automatic.get(code);
    const override = overrides.get(code);
    if (!override) return { ...base, userOverride: false, valueSource: 'automatic', priority: 'automatic', overrideFields: [] };
    const fields = overrideFields(override);
    const result = { ...(base || override), ...override, userOverride: true,
      automaticStatus: base?.status ?? override.automaticStatus ?? null,
      automaticLimit: base?.limit ?? override.automaticLimit ?? null,
      valueSource: 'user', priority: 'user', overrideFields: fields };
    if (base) {
      if (!fields.includes('status')) result.status = base.status;
      if (!fields.includes('limit')) result.limit = base.limit;
    }
    delete result.userId;
    result.userOverride = true;
    return result;
  });
}

function mergeAutomaticQuotas(fresh, old = []) {
  const previous = old || [];
  const oldOverrides = new Map();
  for (const item of previous) {
    if (isUserOverride(item)) {
      if (!oldOverrides.has(item.code)) oldOverrides.set(item.code, []);
      oldOverrides.get(item.code).push(item);
    }
  }
  const merged = [];
  for (const item of fresh) {
    const overrides = oldOverrides.get(item.code) || [];
    for (const current of overrides) {
      const fields = overrideFields(current);
      const preserved = { ...item, status: fields.includes('status') ? current.status : item.status,
        limit: fields.includes('limit') ? current.limit : item.limit, userOverride: true,
        automaticStatus: item.status, automaticLimit: item.limit, userId: current.userId,
        overrideFields: fields, valueSource: 'user', priority: 'user' };
      merged.push(preserved);
    }
    merged.push({ ...item, userOverride: false, valueSource: 'automatic', priority: 'automatic', overrideFields: [] });
  }
  return merged;
}

function restoreAutomaticQuota(records = [], fresh, ownerId) {
  if (!fresh?.code) return records || [];
  const matching = (records || []).filter(item => item?.code === fresh.code);
  const rebuilt = mergeAutomaticQuotas([fresh], matching)
    .filter(item => !(isUserOverride(item) && item.userId === ownerId));
  return (records || []).filter(item => item?.code !== fresh.code).concat(rebuilt);
}
module.exports = { amountFromText, classifyFund, isCandidate, parseQuotaPage, mergeAutomaticQuotas,
  restoreAutomaticQuota, isUserOverride, overrideFields, quotaPriority, visibleQuotas };
