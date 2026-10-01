const { createQuotaSources } = require('./registry');

function createQuotaCollector({ fetchImpl, supplemental = {} } = {}) {
  const sources = createQuotaSources({ fetchImpl, supplemental });
  async function collect(fund) {
    const results = [];
    const errors = [];
    for (const source of sources) {
      if (!source.canHandle(fund)) continue;
      try { results.push(await source.fetch(fund)); }
      catch (error) { errors.push({ adapterId: source.id, channel: source.channel, error: error.message }); }
    }
    return { fund, results, errors };
  }
  return { sources, collect };
}

module.exports = { createQuotaCollector };

