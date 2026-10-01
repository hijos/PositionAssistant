const { normalizeChannel, managerCode } = require('../quotas');

function parseDirectPage(html, fund, { sourceUrl, adapterId = 'fund-manager-direct-v1' } = {}) {
  const clean = String(html || '').replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/\s+/g, ' ').trim();
  const statusText = clean.match(/(?:交易状态|申购状态|销售状态)[：:\s]*([^。；|]{2,30})/);
  const limitText = clean.match(/(?:单日累计购买上限|单日申购上限|单日限额)[：:\s]*([0-9]+(?:\.[0-9]+)?)\s*(万|亿)?元/);
  const parsedAmount = limitText ? Number(limitText[1]) * (limitText[2] === '万' ? 10000 : limitText[2] === '亿' ? 100000000 : 1) : null;
  const status = statusText ? (/(暂停|不开放|关闭)/.test(statusText[1]) ? '暂停申购' : /限/.test(statusText[1]) ? '限大额' : /开放|正常/.test(statusText[1]) ? '开放申购' : '未知') : '未知';
  const amount = status === '暂停申购' ? 0 : parsedAmount;
  const updatedAt = new Date().toISOString();
  return { code: fund.code, name: fund.name, category: fund.category, managerCode: managerCode(fund), channels: { direct: normalizeChannel({ status, limit: amount, directPlatform: fund.directPlatform || 'fund-company-web', source: fund.directSource || '基金公司直销公开页面', sourceType: fund.directSourceType || 'fund-manager-page', sourceUrl, updatedAt, adapterId }) } };
}

function createFundManagerSource({ fetchImpl } = {}) {
  return {
    id: 'fund-manager-direct-v1',
    channel: 'direct',
    canHandle: fund => Boolean(fund?.directUrl) && fund.managerCode !== 'southern',
    async fetch(fund) {
      const response = await (fetchImpl || global.fetch)(fund.directUrl, { headers: { 'User-Agent': 'Mozilla/5.0' } });
      if (!response.ok) throw Error(`direct page ${response.status}`);
      return parseDirectPage(await response.text(), fund, { sourceUrl: fund.directUrl });
    }
  };
}

module.exports = { createFundManagerSource, parseDirectPage };
