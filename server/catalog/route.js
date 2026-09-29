function catalogHandler(service) {
  return async (req, res) => {
    try { res.json(await service.get()); }
    catch { res.status(503).json({ error: '基金目录暂时不可用，且无可用缓存' }); }
  };
}
module.exports = { catalogHandler };
