const { normalizeChannel, managerCode } = require('../quotas');
function parseSouthernStatus(raw) { if (Number(raw) === 0) return '暂停申购'; if (Number(raw) === 1) return '开放申购'; return '未知'; }
function parseSouthernLimit(remark) {
  const match = String(remark || '').match(/(?:大额申购|申购|直销渠道).*?限(?:额|制)(?:调整为)?\s*([0-9]+(?:\.[0-9]+)?)\s*(万|亿)?元/);
  if (!match) return null;
  const amount = Number(match[1]); return match[2] === '万' ? amount * 10000 : match[2] === '亿' ? amount * 100000000 : amount;
}
function normalizeSouthernRecord(record, fund, sourceUrl) {
  const updatedAt = new Date().toISOString(); const status = parseSouthernStatus(record?.sgStatus); const parsedLimit = parseSouthernLimit(record?.remark); const limit = status === '暂停申购' ? 0 : parsedLimit;
  const effectiveMatch = String(record?.remark || '').match(/自(\d{4}年\d{1,2}月\d{1,2}日)起/); const effectiveFrom = effectiveMatch ? effectiveMatch[1].replace(/年|月/g, '-').replace('日', '') : null;
  return { code: fund.code, name: fund.name || record?.fundName, category: fund.category, managerCode: managerCode(fund), officialRestriction: { status, limit, remark: record?.remark || null, channelScope: 'fund-manager-official-default-direct', sourceUrl, observedAt: updatedAt }, channels: { direct: normalizeChannel({ status, limit, directPlatform: 'fund-company-api', source: '南方基金申购赎回状态接口', sourceType: 'fund-manager-api', error: null, sourceUrl, effectiveFrom, updatedAt, adapterId: 'southern-subscription-status-v1', detail: record?.remark || null }) } };
}
function createSouthernSource({ fetchImpl } = {}) { return { id: 'southern-subscription-status-v1', channel: 'direct', canHandle: fund => fund?.managerCode === 'southern' || fund?.directApi === 'southern-subscription-status', async fetch(fund) { const response = await (fetchImpl || global.fetch)('https://www.nffund.com/nfwebApi/customer/subscriptionAndRedemptionStatus', { method: 'POST', headers: { 'User-Agent': 'Mozilla/5.0', 'Content-Type': 'application/json', Referer: 'https://www.nffund.com/new/transaction-guide/product-status-and-limits.html' }, body: '{}' }); if (!response.ok) throw Error(`southern status ${response.status}`); const body = await response.json(); if (body?.code !== 'ETS-5BP00000' || !Array.isArray(body?.data?.fundlist)) throw Error('南方基金申购状态响应无效'); const record = body.data.fundlist.find(item => String(item.fundCode) === String(fund.code)); if (!record) throw Error(`南方基金未找到 ${fund.code}`); return normalizeSouthernRecord(record, fund, 'https://www.nffund.com/new/transaction-guide/product-status-and-limits.html'); } }; }
module.exports = { createSouthernSource, parseSouthernLimit, normalizeSouthernRecord };
