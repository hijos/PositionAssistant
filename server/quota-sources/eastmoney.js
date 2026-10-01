const { parseQuotaPage } = require('../quotas');

function createEastmoneySource({ fetchImpl, supplemental = {} } = {}) {
  return {
    id: 'eastmoney-distribution-v2',
    channel: 'distribution',
    canHandle: fund => Boolean(fund?.code),
    async fetch(fund) {
      const response = await (fetchImpl || global.fetch)(`https://fund.eastmoney.com/${fund.code}.html`, { headers: { 'User-Agent': 'Mozilla/5.0' } });
      if (!response.ok) throw Error(`fund page ${response.status}`);
      const html = await response.text();
      return parseQuotaPage(html, fund, supplemental);
    }
  };
}

module.exports = { createEastmoneySource };

