const test = require('node:test');
const assert = require('node:assert/strict');
const { addCalendarDays, eligibleNavStartDate, selectNextNavDate } = require('../server/trading-date');

test('15:00 前使用当日净值起点，15:00 后使用下一自然日起点', () => {
  assert.equal(eligibleNavStartDate('2026-09-24', 'before'), '2026-09-24');
  assert.equal(eligibleNavStartDate('2026-09-24', 'after'), '2026-09-25');
  assert.equal(addCalendarDays('2026-09-24', 8), '2026-10-02');
});

test('周五 15:00 后跳过周末并匹配下一个有正式净值的交易日', () => {
  const rows = [{ navDate: '2026-09-25' }, { navDate: '2026-09-28' }, { navDate: '2026-09-29' }];
  assert.equal(selectNextNavDate('2026-09-25', 'after', rows), '2026-09-28');
});

test('周末或节假日没有历史记录时继续跳到首个可用净值日', () => {
  const rows = [
    { navDate: '2026-10-09' },
    { navDate: '2026-10-12' },
  ];
  assert.equal(selectNextNavDate('2026-10-01', 'before', rows), '2026-10-09');
  assert.equal(selectNextNavDate('2026-10-01', 'after', rows), '2026-10-09');
  assert.equal(selectNextNavDate('2026-10-10', 'before', rows), '2026-10-12');
});

test('没有已公布的后续净值时返回待确认所需的空结果', () => {
  assert.equal(selectNextNavDate('2026-09-30', 'after', [{ navDate: '2026-09-30' }]), null);
});

test('拒绝无效日期和交易时间', () => {
  assert.throws(() => eligibleNavStartDate('2026-02-30', 'before'), /交易日期无效/);
  assert.throws(() => eligibleNavStartDate('2026-09-24', 'at15'), /交易时间无效/);
});
