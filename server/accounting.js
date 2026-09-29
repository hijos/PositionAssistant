const MONEY_DECIMALS = 2;

function round(value) {
  if (!Number.isFinite(value)) throw new Error('金额、份额和净值必须是有效数字');
  const scale = 10 ** MONEY_DECIMALS;
  return Math.round((value + Number.EPSILON) * scale) / scale;
}

function positiveNumber(value, label, shouldRound = true) {
  const number = Number(value);
  if (!Number.isFinite(number) || number <= 0) throw new Error(`${label}必须大于0`);
  return shouldRound ? round(number) : number;
}

function resolveFeeMode(transaction) {
  if (transaction.feeMode != null) {
    const mode = String(transaction.feeMode);
    if (mode !== 'rate' && mode !== 'fixed') throw new Error('手续费模式无效');
    return mode;
  }
  if (transaction.fixedFee != null) return 'fixed';
  if (transaction.feeRate != null) return 'rate';
  // Historical JSON transactions only have the already calculated `fee`.
  return 'fixed';
}

function resolveFee(transaction, baseAmount, amountInput) {
  const mode = resolveFeeMode(transaction);
  if (mode === 'rate') {
    const feeRate = Number(transaction.feeRate ?? 0);
    if (!Number.isFinite(feeRate) || feeRate < 0 || feeRate >= 100) {
      throw new Error('手续费率必须在0至100%之间');
    }
    const rate = feeRate / 100;
    return {
      feeMode: mode,
      feeRate,
      fixedFee: null,
      fee: round(transaction.type === 'buy' && transaction.entryMode === 'amount'
        ? amountInput - amountInput / (1 + rate)
        : baseAmount * rate),
    };
  }

  const raw = transaction.fixedFee ?? transaction.fee ?? 0;
  const fixedFee = Number(raw);
  if (!Number.isFinite(fixedFee) || fixedFee < 0) throw new Error('固定手续费必须是非负数字');
  const fee = round(fixedFee);
  if (transaction.type === 'buy' && transaction.entryMode === 'amount' && fee > amountInput) {
    throw new Error('固定手续费不能大于买入金额');
  }
  return {feeMode: mode, feeRate: null, fixedFee: fee, fee};
}

function calculate(transaction, nav) {
  const price = positiveNumber(nav, '净值', false);
  const amountInput = transaction.entryMode === 'amount' ? positiveNumber(transaction.amount, '金额') : 0;
  const sharesInput = transaction.entryMode === 'shares' ? positiveNumber(transaction.shares, '份额') : 0;
  if (!['buy', 'sell'].includes(transaction.type)) throw new Error('交易类型无效');
  if (!['amount', 'shares'].includes(transaction.entryMode)) throw new Error('填写方式无效');

  const baseAmount = transaction.entryMode === 'shares' ? round(sharesInput * price) : amountInput;
  const resolved = resolveFee(transaction, baseAmount, amountInput);
  let amount = transaction.entryMode === 'shares' ? baseAmount : amountInput;
  let shares = sharesInput;
  if (transaction.entryMode === 'shares') {
    if (transaction.type === 'buy') amount = round(baseAmount + resolved.fee);
  } else {
    const netAmount = transaction.type === 'buy' ? amountInput - resolved.fee : amountInput;
    if (netAmount <= 0) throw new Error('扣除手续费后金额必须大于0');
    shares = round(netAmount / price);
  }

  return {
    ...transaction,
    amount: round(amount),
    shares: round(shares),
    feeMode: resolved.feeMode,
    feeRate: resolved.feeRate,
    fixedFee: resolved.fixedFee,
    fee: resolved.fee,
    tradeNav: price,
    status: 'confirmed',
    pendingReason: null,
  };
}

function holdings(transactions, funds) {
  const out = {};
  for (const t of [...transactions].filter(t => t.status === 'confirmed').sort((a, b) => a.date.localeCompare(b.date) || (a.cutoff === 'after') - (b.cutoff === 'after'))) {
    const h = out[t.fundCode] ||= {
      fundCode: t.fundCode,
      shares: 0,
      // `invested` is the cumulative cash committed by confirmed buys.
      invested: 0,
      // `redeemed` is the net cash received from confirmed sells.
      redeemed: 0,
      cost: 0,
      realizedProfit: 0,
      transactions: 0,
    };
    const shares = Number(t.shares || 0);
    if (t.type === 'buy') {
      h.shares += shares;
      const amount = Number(t.amount || 0);
      h.invested += amount;
      h.cost += amount;
    } else {
      if (shares > h.shares + 0.000001) throw Error('卖出份额超过当时持仓，请先撤销相关卖出记录');
      const cost = h.shares ? h.cost * shares / h.shares : 0;
      const proceeds = Number(t.amount || 0) - Number(t.fee || 0);
      h.redeemed += proceeds;
      h.realizedProfit += proceeds - cost;
      h.cost -= cost;
      h.shares -= shares;
    }
    h.transactions++;
  }
  return Object.values(out).map(h => {
    const f = funds.find(f => f.code === h.fundCode);
    const valid = f?.nav > 0 && !!f.navDate;
    const estimated = valid && f.estimatedNav > 0 && (f.estimateBaseDate === f.navDate || f.estimateAt?.slice(0, 10) > f.navDate) && Date.now() - Date.parse(/Z$|[+-]\d{2}:\d{2}$/.test(f.estimateAt) ? f.estimateAt : f.estimateAt + '+08:00') < 4 * 86400000;
    // Formal valuation is only available when a positive official NAV and its
    // date are present. Keep monetary fields at the same two-decimal precision
    // as the ledger so clients can display stable values.
    const marketValue = valid ? round(h.shares * f.nav) : null;
    const profit = valid ? round(marketValue - h.cost) : null;
    // The estimate keeps the same definition as the formal valuation so the
    // client can show "预估市值" next to "预估收益": shares x estimatedNav.
    const estimatedMarketValue = estimated ? round(h.shares * f.estimatedNav) : null;
    const estimatedProfit = estimated ? h.shares * f.estimatedNav - h.cost : null;
    return {
      ...h,
      shares: round(h.shares),
      invested: round(h.invested),
      redeemed: round(h.redeemed),
      cost: round(h.cost),
      realizedProfit: round(h.realizedProfit),
      nav: valid ? f.nav : null,
      navDate: f?.navDate,
      marketValue,
      profit,
      profitRate: h.cost && valid ? profit / h.cost : null,
      estimatedMarketValue,
      estimatedProfit,
      estimatedProfitRate: h.cost && estimatedMarketValue != null ? estimatedProfit / h.cost : null,
      estimateAt: f?.estimateAt,
      estimateSource: f?.estimateSource,
      sourceError: f?.sourceError,
      estimateCoverage: f?.estimateCoverage,
      holdingsDate: f?.holdingsDate,
      estimateMethod: f?.estimateMethod,
      estimateError: f?.estimateError,
    };
  });
}

function transactionOrder(a, b) {
  return String(a.date || '').localeCompare(String(b.date || ''))
    || (a.cutoff === 'after') - (b.cutoff === 'after')
    || String(a.id || '').localeCompare(String(b.id || ''));
}

function normalizeNavHistory(rows) {
  const byDate = new Map();
  for (const row of rows || []) {
    const nav = Number(row?.nav);
    const navDate = String(row?.navDate || '');
    if (Number.isFinite(nav) && nav > 0 && /^\d{4}-\d{2}-\d{2}$/.test(navDate)) byDate.set(navDate, nav);
  }
  return [...byDate.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([navDate, nav]) => ({navDate, nav}));
}

/**
 * Calculate formal daily returns from official NAV dates.
 * `cashFlow` is the net amount invested that day (buy amount minus net sell proceeds).
 * The first NAV date is omitted because there is no prior official valuation to compare.
 */
function dailyFormalReturns(transactions, navHistoryByFund) {
  const confirmed = (transactions || []).filter(t => t.status === 'confirmed').sort(transactionOrder);
  const fundCodes = new Set(confirmed.map(t => t.fundCode));
  const result = [];
  for (const fundCode of fundCodes) {
    const navs = normalizeNavHistory(navHistoryByFund?.[fundCode]);
    if (navs.length < 2) continue;
    const fundTransactions = confirmed.filter(t => t.fundCode === fundCode && /^\d{4}-\d{2}-\d{2}$/.test(String(t.navDate || '')));
    let txIndex = 0;
    let shares = 0;
    let previousMarketValue = null;
    for (const {navDate, nav} of navs) {
      let cashFlow = 0;
      while (txIndex < fundTransactions.length && fundTransactions[txIndex].navDate <= navDate) {
        const t = fundTransactions[txIndex++];
        const txShares = Number(t.shares || 0);
        if (!Number.isFinite(txShares) || txShares < 0) continue;
        shares += t.type === 'sell' ? -txShares : txShares;
        if (t.navDate === navDate) {
          const amount = Number(t.amount || 0);
          const fee = Number(t.fee || 0);
          if (t.type === 'sell') cashFlow -= amount - fee;
          else cashFlow += amount;
        }
      }
      const marketValue = round(Math.max(0, shares) * nav);
      if (previousMarketValue !== null) {
        result.push({
          fundCode,
          navDate,
          marketValue,
          previousMarketValue,
          cashFlow: round(cashFlow),
          profit: round(marketValue - previousMarketValue - cashFlow),
        });
      }
      previousMarketValue = marketValue;
    }
  }
  return result.sort((a, b) => a.navDate.localeCompare(b.navDate) || a.fundCode.localeCompare(b.fundCode));
}

module.exports = {calculate, holdings, dailyFormalReturns, round};
