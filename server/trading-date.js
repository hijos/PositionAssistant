const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const DAY_MS = 24 * 60 * 60 * 1000;

function assertDate(value, label = '交易日期') {
  if (typeof value !== 'string' || !DATE_PATTERN.test(value)) throw new Error(`${label}无效`);
  const parsed = Date.parse(`${value}T00:00:00Z`);
  if (!Number.isFinite(parsed) || new Date(parsed).toISOString().slice(0, 10) !== value) {
    throw new Error(`${label}无效`);
  }
  return value;
}

function addCalendarDays(date, days) {
  assertDate(date);
  if (!Number.isInteger(days)) throw new Error('日期偏移必须是整数');
  return new Date(Date.parse(`${date}T00:00:00Z`) + days * DAY_MS).toISOString().slice(0, 10);
}

function eligibleNavStartDate(tradeDate, cutoff) {
  assertDate(tradeDate);
  if (cutoff !== 'before' && cutoff !== 'after') throw new Error('交易时间无效');
  return cutoff === 'after' ? addCalendarDays(tradeDate, 1) : tradeDate;
}

/**
 * Select the first official NAV date on or after the cutoff-adjusted date.
 * The official history is the source of truth for weekends and exchange holidays:
 * dates absent from that history are skipped without maintaining a holiday table.
 */
function selectNextNavDate(tradeDate, cutoff, rows) {
  const startDate = eligibleNavStartDate(tradeDate, cutoff);
  const dates = [...new Set((Array.isArray(rows) ? rows : [])
    .map(row => typeof row === 'string' ? row : row?.navDate)
    .filter(date => typeof date === 'string' && DATE_PATTERN.test(date)))]
    .filter(date => {
      try { assertDate(date, '净值日期'); return true; } catch { return false; }
    })
    .sort();
  return dates.find(date => date >= startDate) || null;
}

module.exports = { addCalendarDays, eligibleNavStartDate, selectNextNavDate };
