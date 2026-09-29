const test = require('node:test');
const assert = require('node:assert/strict');
const {calculate, holdings, dailyFormalReturns} = require('../server/accounting');
const {validateTrade} = require('../server');

const trade = (overrides = {}) => ({
  fundCode: '000001', type: 'buy', entryMode: 'amount', amount: 101, shares: 0,
  date: '2026-09-01', cutoff: 'before', ...overrides,
});

test('费率按金额和份额换算，并保留两位金额/份额', () => {
  const byAmount = calculate(trade({feeMode: 'rate', feeRate: 1}), 2);
  assert.deepEqual({amount: byAmount.amount, shares: byAmount.shares, fee: byAmount.fee}, {amount: 101, shares: 50, fee: 1});
  const byShares = calculate(trade({type: 'sell', entryMode: 'shares', amount: 0, shares: 20, feeMode: 'rate', feeRate: 1}), 3);
  assert.deepEqual({amount: byShares.amount, shares: byShares.shares, fee: byShares.fee}, {amount: 60, shares: 20, fee: 0.6});
});

test('固定费用按买入含费、卖出扣费前金额计算', () => {
  const buyByAmount = calculate(trade({feeMode: 'fixed', fixedFee: 1}), 2);
  assert.deepEqual({amount: buyByAmount.amount, shares: buyByAmount.shares, fee: buyByAmount.fee}, {amount: 101, shares: 50, fee: 1});
  const buyByShares = calculate(trade({entryMode: 'shares', amount: 0, shares: 50, feeMode: 'fixed', fixedFee: 1}), 2);
  assert.deepEqual({amount: buyByShares.amount, shares: buyByShares.shares, fee: buyByShares.fee}, {amount: 101, shares: 50, fee: 1});
  const sellByAmount = calculate(trade({type: 'sell', feeMode: 'fixed', fixedFee: 0.6}), 3);
  assert.deepEqual({amount: sellByAmount.amount, shares: sellByAmount.shares, fee: sellByAmount.fee}, {amount: 101, shares: 33.67, fee: 0.6});
  const sellByShares = calculate(trade({type: 'sell', entryMode: 'shares', amount: 0, shares: 20, feeMode: 'fixed', fixedFee: 0.6}), 3);
  assert.deepEqual({amount: sellByShares.amount, shares: sellByShares.shares, fee: sellByShares.fee}, {amount: 60, shares: 20, fee: 0.6});
});

test('历史只有 fee 的交易仍按固定费用兼容', () => {
  const result = calculate(trade({fee: 1, feeRate: undefined}), 2);
  assert.equal(result.fee, 1);
  assert.equal(result.shares, 50);
});

test('交易输入校验支持费率或固定费用且拒绝混用', () => {
  const date = new Date().toLocaleDateString('en-CA', {timeZone: 'Asia/Shanghai'});
  const rate = validateTrade(trade({date, feeRate: 0.15}));
  assert.equal(rate.feeMode, 'rate');
  assert.equal(rate.feeRate, 0.15);
  const fixed = validateTrade(trade({date, feeMode: 'fixed', fixedFee: 1.5}));
  assert.equal(fixed.feeMode, 'fixed');
  assert.equal(fixed.fixedFee, 1.5);
  assert.throws(() => validateTrade(trade({date, feeMode: 'rate', feeRate: 1, fixedFee: 1})), /只能二选一/);
  assert.throws(() => validateTrade(trade({date, feeMode: 'fixed', fixedFee: -1})), /非负/);
  assert.throws(() => validateTrade(trade({date, feeMode: 'rate', feeRate: 100})), /0至100/);
});

test('无效净值、手续费和扣费后金额会被拒绝', () => {
  assert.throws(() => calculate(trade({feeMode: 'fixed', fixedFee: 102}), 2), /不能大于买入金额/);
  assert.throws(() => calculate(trade(), 0), /净值必须大于0/);
  assert.throws(() => calculate(trade({feeMode: 'rate', feeRate: 100}), 2), /0至100/);
});

test('买入和卖出换算后的持仓成本与已实现收益保持一致', () => {
  const buy = calculate(trade({feeMode: 'fixed', fixedFee: 1}), 2);
  const sell = calculate(trade({type: 'sell', entryMode: 'shares', amount: 0, shares: 20, feeMode: 'fixed', fixedFee: 0.6, date: '2026-09-02'}), 3);
  const result = holdings([buy, sell], [{code: '000001', nav: 3, navDate: '2026-09-03'}])[0];
  assert.equal(result.shares, 30);
  assert.equal(result.invested, 101);
  assert.equal(result.redeemed, 59.4);
  assert.equal(result.cost, 60.6);
  assert.ok(Math.abs(result.realizedProfit - 19) < 0.00001);
});

test('汇总只纳入已确认交易并按基金分组', () => {
  const confirmedBuy = calculate(trade({fundCode: '000001', feeMode: 'fixed', fixedFee: 1}), 2);
  const confirmedSell = calculate(trade({
    fundCode: '000001', type: 'sell', entryMode: 'shares', amount: 0, shares: 10,
    feeMode: 'fixed', fixedFee: 0.5, date: '2026-09-02',
  }), 3);
  const otherFund = calculate(trade({fundCode: '000002', amount: 50, feeMode: 'fixed', fixedFee: 0}), 1);
  const pending = {...calculate(trade({fundCode: '000001', amount: 20}), 2), status: 'pending'};
  const cancelled = {...calculate(trade({fundCode: '000001', amount: 30}), 2), status: 'cancelled'};

  const result = holdings(
    [confirmedBuy, confirmedSell, otherFund, pending, cancelled],
    [{code: '000001', nav: 3, navDate: '2026-09-03'}, {code: '000002', nav: 1, navDate: '2026-09-03'}],
  );
  assert.deepEqual(result.map(item => item.fundCode), ['000001', '000002']);
  assert.deepEqual(
    result[0] && {
      shares: result[0].shares,
      invested: result[0].invested,
      redeemed: result[0].redeemed,
      cost: result[0].cost,
      transactions: result[0].transactions,
    },
    {shares: 40, invested: 101, redeemed: 29.5, cost: 80.8, transactions: 2},
  );
  assert.deepEqual(
    result[1] && {shares: result[1].shares, invested: result[1].invested, redeemed: result[1].redeemed, cost: result[1].cost},
    {shares: 50, invested: 50, redeemed: 0, cost: 50},
  );
});

test('多笔卖出按历史持仓校验并在清仓后拒绝超卖', () => {
  const buy = calculate(trade({entryMode: 'shares', amount: 0, shares: 100, feeMode: 'fixed', fixedFee: 0}), 2);
  const firstSell = calculate(trade({type: 'sell', entryMode: 'shares', amount: 0, shares: 40, feeMode: 'fixed', fixedFee: 0, date: '2026-09-02'}), 3);
  const finalSell = calculate(trade({type: 'sell', entryMode: 'shares', amount: 0, shares: 60, feeMode: 'fixed', fixedFee: 0, date: '2026-09-03'}), 3);
  const result = holdings([buy, firstSell, finalSell], [{code: '000001', nav: 3, navDate: '2026-09-04'}])[0];
  assert.equal(result.shares, 0);
  assert.equal(result.cost, 0);
  assert.throws(() => holdings([
    buy,
    firstSell,
    finalSell,
    calculate(trade({type: 'sell', entryMode: 'shares', amount: 0, shares: 0.01, feeMode: 'fixed', fixedFee: 0, date: '2026-09-04'}), 3),
  ], [{code: '000001', nav: 3, navDate: '2026-09-05'}]), /超过当时持仓/);
});

test('历史顺序和待确认状态参与卖出校验', () => {
  const buy = calculate(trade({entryMode: 'shares', amount: 0, shares: 10, feeMode: 'fixed', fixedFee: 0, date: '2026-09-02'}), 2);
  const pendingSell = {...calculate(trade({type: 'sell', entryMode: 'shares', amount: 0, shares: 20, feeMode: 'fixed', fixedFee: 0, date: '2026-09-01'}), 3), status: 'pending'};
  assert.equal(holdings([buy, pendingSell], [{code: '000001', nav: 2, navDate: '2026-09-03'}])[0].shares, 10);
  assert.throws(() => holdings([
    calculate(trade({type: 'sell', entryMode: 'shares', amount: 0, shares: 1, feeMode: 'fixed', fixedFee: 0, date: '2026-09-01'}), 3),
    buy,
  ], [{code: '000001', nav: 2, navDate: '2026-09-03'}]), /超过当时持仓/);
});

test('正式净值生成市值、持有收益和收益率，缺失净值时保持待定', () => {
  const buy = calculate(trade({entryMode: 'shares', amount: 0, shares: 10, feeMode: 'fixed', fixedFee: 0}), 2);
  const sell = calculate(trade({type: 'sell', entryMode: 'shares', amount: 0, shares: 2, feeMode: 'fixed', fixedFee: 0.1, date: '2026-09-02'}), 3);
  const [valued, unvalued] = holdings(
    [buy, sell, {...buy, fundCode: '000002', status: 'pending'}],
    [
      {code: '000001', nav: 3.456, navDate: '2026-09-24'},
      {code: '000002'},
    ],
  );
  assert.deepEqual(
    {
      shares: valued.shares,
      cost: valued.cost,
      marketValue: valued.marketValue,
      profit: valued.profit,
    },
    {shares: 8, cost: 16, marketValue: 27.65, profit: 11.65},
  );
  assert.ok(Math.abs(valued.profitRate - 11.65 / 16) < 1e-12);
  assert.equal(valued.navDate, '2026-09-24');
  assert.equal(unvalued, undefined, '待确认交易不应创建持仓汇总');
});

test('持仓成本为零时正式收益率为空', () => {
  const buy = calculate(trade({entryMode: 'shares', amount: 0, shares: 10, feeMode: 'fixed', fixedFee: 0}), 2);
  const sell = calculate(trade({type: 'sell', entryMode: 'shares', amount: 0, shares: 10, feeMode: 'fixed', fixedFee: 0, date: '2026-09-02'}), 2);
  const result = holdings([buy, sell], [{code: '000001', nav: 3, navDate: '2026-09-24'}])[0];
  assert.equal(result.shares, 0);
  assert.equal(result.cost, 0);
  assert.equal(result.marketValue, 0);
  assert.equal(result.profit, 0);
  assert.equal(result.profitRate, null);
});

test('每日正式收益按现金流调整并排除待确认及取消交易', () => {
  const buy = calculate(trade({entryMode: 'shares', amount: 0, shares: 10, feeMode: 'fixed', fixedFee: 1, date: '2026-09-01'}), 10);
  buy.navDate = '2026-09-01';
  const sell = calculate(trade({type: 'sell', entryMode: 'shares', amount: 0, shares: 2, feeMode: 'fixed', fixedFee: 0.2, date: '2026-09-02'}), 12);
  sell.navDate = '2026-09-02';
  const pending = {...buy, status: 'pending', navDate: '2026-09-02'};
  const cancelled = {...buy, status: 'cancelled', navDate: '2026-09-02'};
  const rows = dailyFormalReturns(
    [buy, sell, pending, cancelled],
    {'000001': [{nav: 10, navDate: '2026-09-01'}, {nav: 12, navDate: '2026-09-02'}, {nav: 13, navDate: '2026-09-03'}]},
  );
  assert.deepEqual(rows, [
    {fundCode: '000001', navDate: '2026-09-02', marketValue: 96, previousMarketValue: 100, cashFlow: -23.8, profit: 19.8},
    {fundCode: '000001', navDate: '2026-09-03', marketValue: 104, previousMarketValue: 96, cashFlow: 0, profit: 8},
  ]);
});

test('每日正式收益按基金隔离且缺少可比较净值时不生成记录', () => {
  const buyA = {...calculate(trade({fundCode: '000001', entryMode: 'shares', amount: 0, shares: 2, feeMode: 'fixed', fixedFee: 0, date: '2026-09-01'}), 10), navDate: '2026-09-01'};
  const buyB = {...calculate(trade({fundCode: '000002', entryMode: 'shares', amount: 0, shares: 3, feeMode: 'fixed', fixedFee: 0, date: '2026-09-01'}), 5), navDate: '2026-09-01'};
  const rows = dailyFormalReturns([buyA, buyB], {
    '000001': [{nav: 10, navDate: '2026-09-01'}, {nav: 11, navDate: '2026-09-03'}],
    '000002': [{nav: 5, navDate: '2026-09-01'}],
  });
  assert.deepEqual(rows, [{fundCode: '000001', navDate: '2026-09-03', marketValue: 22, previousMarketValue: 20, cashFlow: 0, profit: 2}]);
});
