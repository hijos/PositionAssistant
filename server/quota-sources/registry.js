const { createEastmoneySource } = require('./eastmoney');
const { createFundManagerSource } = require('./fund-manager');
const { createSouthernSource } = require('./southern');

function createQuotaSources(options = {}) {
  return [
    createSouthernSource(options),
    createEastmoneySource(options),
    createFundManagerSource(options)
  ];
}

module.exports = { createQuotaSources };

