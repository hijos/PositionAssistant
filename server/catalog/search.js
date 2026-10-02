// fundcode_search has no explicit currency or trading-venue fields. Apply a
// conservative name/type policy; keep the raw catalog available for consumers.
function supportedFund(item) {
  const name = item.name.normalize('NFKC').toUpperCase();
  const type = item.type.normalize('NFKC').toUpperCase();
  const text = `${name} ${type}`;
  if (/美元|美钞|美汇|港币|港元|欧元|英镑|日元|澳元|加元|新加坡元|瑞士法郎|外币|外汇|USD|HKD|EUR|GBP|JPY|AUD|CAD|SGD|CHF/.test(text)) return false;
  if (/LOF|场内|交易型|封闭|REIT/.test(text)) return false;
  if (/ETF/.test(text) && !/ETF[^\n]{0,24}(联接|连接)/.test(name)) return false;
  return /^(股票型|混合型|债券型|货币型|指数型|QDII|FOF)(-|$)/.test(type);
}
function queryText(value) {
  if (value === undefined) return '';
  if (typeof value !== 'string' || value.length > 100) throw new Error('请输入不超过100个字符的基金名称或代码');
  return value.normalize('NFKC').trim().toLowerCase();
}
function searchFunds(items, query) {
  if (!query) return [];
  return items.filter(supportedFund).filter(item =>
    [item.code, item.name, item.shortName].some(value => value.normalize('NFKC').toLowerCase().includes(query)))
    .sort((a, b) => Number(b.code === query) - Number(a.code === query) || a.code.localeCompare(b.code))
    .slice(0, 20);
}
function searchHandler(service) {
  return async (req, res) => {
    let query;
    try { query = queryText(req.query.q); }
    catch (error) { return res.status(400).json({ error: error.message }); }
    if (!query) return res.json([]);
    try { return res.json(searchFunds((await service.get()).items, query)); }
    catch { return res.status(503).json({ error: '基金目录暂时不可用，且无可用缓存' }); }
  };
}
module.exports = { supportedFund, queryText, searchFunds, searchHandler };
