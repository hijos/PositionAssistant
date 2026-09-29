const { Pool } = require('pg');
const { supportedFund } = require('../catalog/search');
class FundStore {
  constructor(pool) { this.pool = pool; }
  async list(owner) {
    return (await this.pool.query('SELECT payload FROM positionassistant.user_funds WHERE owner_id=$1 ORDER BY code', [owner])).rows.map(row => row.payload);
  }
  async add(owner, fund) {
    await this.pool.query('INSERT INTO positionassistant.user_funds(owner_id,code,payload) VALUES($1,$2,$3::jsonb) ON CONFLICT(owner_id,code) DO NOTHING', [owner, fund.code, JSON.stringify(fund)]);
    return (await this.pool.query('SELECT payload FROM positionassistant.user_funds WHERE owner_id=$1 AND code=$2', [owner, fund.code])).rows[0].payload;
  }
  async remove(owner, code) {
    const result = await this.pool.query(
      'DELETE FROM positionassistant.user_funds WHERE owner_id=$1 AND code=$2',
      [owner, code],
    );
    return result.rowCount > 0;
  }
}
function installFundRoutes(app, { user, catalog, store }) {
  app.use('/api/my-funds', (req, res, next) => {
    const owner = user(req);
    if (!owner) return res.status(401).json({error:'请先登录'});
    req.fundOwner = owner;
    next();
  });
  app.get('/api/my-funds', async (req, res) => {
    try { res.json(await store.list(req.fundOwner)); }
    catch { res.status(503).json({error:'基金列表暂时不可用'}); }
  });
  app.post('/api/my-funds', async (req, res) => {
    const code = req.body?.code;
    if (typeof code !== 'string' || !/^\d{6}$/.test(code)) return res.status(400).json({error:'基金代码必须为六位数字'});
    try {
      // Retries do not require a fresh catalog and never overwrite saved metadata.
      const existing = (await store.list(req.fundOwner)).find(f => f.code === code);
      if (existing) return res.json(existing);
      const item = (await catalog.get()).items.find(f => f.code === code);
      if (!item || !supportedFund(item)) return res.status(400).json({error:'请选择目录中的人民币场外基金'});
      const fund = {code:item.code, name:item.name, type:item.type};
      res.json(await store.add(req.fundOwner, fund));
    } catch { res.status(503).json({error:'添加失败，请稍后重试'}); }
  });
  app.delete('/api/my-funds/:code', async (req, res) => {
    const { code } = req.params;
    if (!/^\d{6}$/.test(code)) return res.status(400).json({error:'基金代码必须为六位数字'});
    try {
      const removed = await store.remove(req.fundOwner, code);
      if (!removed) return res.status(404).json({error:'基金不存在'});
      res.sendStatus(204);
    } catch { res.status(503).json({error:'删除失败，请稍后重试'}); }
  });
}
module.exports = { FundStore, installFundRoutes, configuredFundStore: () => new FundStore(new Pool({connectionString:process.env.DATABASE_URL})) };
