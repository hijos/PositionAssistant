const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');

const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'position-transactions-'));
const dbPath = path.join(tempDir, 'db.json');
fs.writeFileSync(dbPath, JSON.stringify({users: [], funds: [], transactions: [], plans: [], quotas: [], fundCatalog: []}));
let navRows = [];
const realFetch = global.fetch;
global.fetch = async url => {
  if (String(url).includes('/f10/lsjz')) {
    return new Response(JSON.stringify({Data: {LSJZList: navRows}}), {status: 200});
  }
  return new Response('{}', {status: 200});
};
process.env.POSITIONASSISTANT_DB_PATH = dbPath;
const {app} = require('../server');

function call(port, method, route, token, body) {
  return new Promise((resolve, reject) => {
    const request = http.request({
      port, method, path: route,
      headers: {Authorization: token ? `Bearer ${token}` : '', ...(body ? {'Content-Type': 'application/json'} : {})},
    }, response => {
      let text = '';
      response.setEncoding('utf8');
      response.on('data', chunk => { text += chunk; });
      response.on('end', () => resolve({status: response.statusCode, body: parseBody(text)}));
    });
    request.on('error', reject);
    if (body) request.write(JSON.stringify(body));
    request.end();
  });
}

// Some endpoints answer with plain text (for example `sendStatus(401)`), so a
// failed parse keeps the raw body instead of throwing.
function parseBody(text) {
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

const draft = requestId => ({
  fundCode: '000001', fundName: '测试基金', fundType: '混合型', type: 'buy',
  entryMode: 'amount', amount: 100, shares: 0, feeMode: 'fixed', feeRate: 0,
  fixedFee: 0, date: new Date().toLocaleDateString('en-CA', {timeZone: 'Asia/Shanghai'}),
  cutoff: 'before', clientRequestId: requestId,
});

// The database file is shared by every test in this file, so the temp
// directory only goes away after the last one.
test.after(() => fs.rmSync(tempDir, {recursive: true, force: true}));

test('待确认交易按账号确认且重复创建幂等', async t => {
  const server = app.listen(0);
  t.after(() => {
    server.close();
    global.fetch = realFetch;
  });
  const port = server.address().port;
  assert.equal((await call(port, 'GET', '/api/daily-returns', null)).status, 401);
  assert.equal((await call(port, 'POST', '/api/auth/register', null, {email: 'a@example.com', password: 'password-a'})).status, 201);
  assert.equal((await call(port, 'POST', '/api/auth/register', null, {email: 'b@example.com', password: 'password-b'})).status, 201);
  const tokenA = (await call(port, 'POST', '/api/auth/login', null, {email: 'a@example.com', password: 'password-a'})).body.token;
  const tokenB = (await call(port, 'POST', '/api/auth/login', null, {email: 'b@example.com', password: 'password-b'})).body.token;

  const [first, retry] = await Promise.all([
    call(port, 'POST', '/api/transactions', tokenA, draft('request-a')),
    call(port, 'POST', '/api/transactions', tokenA, draft('request-a')),
  ]);
  assert.ok([201, 200].includes(first.status));
  assert.ok([201, 200].includes(retry.status));
  assert.equal(first.body.id, retry.body.id);
  assert.equal((await call(port, 'GET', '/api/transactions', tokenA)).body.length, 1);
  assert.deepEqual((await call(port, 'GET', '/api/holdings', tokenA)).body, []);

  const other = await call(port, 'POST', '/api/transactions', tokenB, draft('request-b'));
  assert.equal(other.status, 201);
  navRows = [{DWJZ: '2.00', FSRQ: draft('x').date}];
  const confirmed = await call(port, 'POST', '/api/transactions/confirm', tokenA);
  assert.equal(confirmed.status, 200);
  assert.equal(confirmed.body.transactions.length, 1);
  assert.equal(confirmed.body.transactions[0].id, first.body.id);
  assert.equal((await call(port, 'GET', '/api/transactions', tokenA)).body[0].status, 'confirmed');
  navRows = [{DWJZ: '2.00', FSRQ: '2026-09-23'}, {DWJZ: '2.00', FSRQ: draft('x').date}];
  const daily = await call(port, 'GET', '/api/daily-returns', tokenA);
  assert.equal(daily.status, 200);
  assert.equal(daily.body.items.at(-1).profit, 0);
  assert.deepEqual((await call(port, 'GET', '/api/daily-returns', tokenB)).body.items, []);
  assert.equal((await call(port, 'GET', '/api/transactions', tokenB)).body[0].status, 'pending');
  assert.deepEqual(
    (await call(port, 'GET', '/api/holdings', tokenB)).body,
    [],
    '待确认交易不应出现在另一账号的持仓汇总中',
  );

  const sellDate = draft('sell-date').date;
  navRows = [{DWJZ: '2.00', FSRQ: sellDate}];
  const sell = await call(port, 'POST', '/api/transactions', tokenA, {
    ...draft('sell-request'), type: 'sell', entryMode: 'shares', amount: 0,
    shares: 10, date: sellDate,
  });
  assert.equal(sell.status, 201);
  assert.equal(sell.body.status, 'confirmed');
  const holding = await call(port, 'GET', '/api/holdings', tokenA);
  assert.equal(holding.status, 200);
  assert.equal(holding.body[0].shares, 40);
  assert.equal(holding.body[0].invested, 100);
  assert.equal(holding.body[0].redeemed, 20);
  assert.equal(holding.body[0].cost, 80);
  assert.equal(holding.body[0].nav, 2);
  assert.equal(holding.body[0].navDate, sellDate);
  assert.equal(holding.body[0].marketValue, 80);
  assert.equal(holding.body[0].profit, 0);
  assert.equal(holding.body[0].profitRate, 0);

  const oversell = await call(port, 'POST', '/api/transactions', tokenA, {
    ...draft('oversell-request'), type: 'sell', entryMode: 'shares', amount: 0,
    shares: 41, date: sellDate,
  });
  assert.equal(oversell.status, 400);
  assert.match(oversell.body.error, /超过当时持仓/);
  assert.equal((await call(port, 'GET', '/api/transactions', tokenA)).body.length, 2);

  const cancelledSell = await call(port, 'DELETE', `/api/transactions/${sell.body.id}`, tokenA);
  assert.equal(cancelledSell.status, 200);
  assert.equal(cancelledSell.body.status, 'cancelled');
  assert.ok(cancelledSell.body.cancelledAt);
  assert.equal((await call(port, 'GET', '/api/holdings', tokenA)).body[0].shares, 50);
  const repeatedCancel = await call(port, 'DELETE', `/api/transactions/${sell.body.id}`, tokenA);
  assert.equal(repeatedCancel.status, 200);
  assert.equal(repeatedCancel.body.cancelledAt, cancelledSell.body.cancelledAt);
  assert.equal((await call(port, 'DELETE', `/api/transactions/${sell.body.id}`, tokenB)).status, 404);
  assert.equal((await call(port, 'DELETE', '/api/transactions/missing', tokenA)).status, 404);

  const pendingB = await call(port, 'DELETE', `/api/transactions/${other.body.id}`, tokenB);
  assert.equal(pendingB.status, 200);
  assert.equal(pendingB.body.status, 'cancelled');

  navRows = [{DWJZ: '2.00', FSRQ: sellDate}];
  const dependentBuy = await call(port, 'POST', '/api/transactions', tokenA, {
    ...draft('dependent-buy'), date: sellDate,
  });
  assert.equal(dependentBuy.status, 201);
  const dependentSell = await call(port, 'POST', '/api/transactions', tokenA, {
    ...draft('dependent-sell'), type: 'sell', entryMode: 'shares', amount: 0,
    shares: 60, date: sellDate,
  });
  assert.equal(dependentSell.status, 201);
  const blocked = await call(port, 'DELETE', `/api/transactions/${dependentBuy.body.id}`, tokenA);
  assert.equal(blocked.status, 409);
  assert.match(blocked.body.error, /超过当时持仓/);
  const unchanged = (await call(port, 'GET', '/api/transactions', tokenA)).body;
  assert.equal(unchanged.find(item => item.id === dependentBuy.body.id).status, 'confirmed');
  assert.equal(unchanged.find(item => item.id === dependentSell.body.id).status, 'confirmed');
});

test('已取消交易可永久删除和批量清理且保持账号隔离', async t => {
  const server = app.listen(0);
  t.after(() => {
    server.close();
    global.fetch = realFetch;
  });
  const port = server.address().port;
  const today = draft('permanent-date').date;
  navRows = [{DWJZ: '2.00', FSRQ: today}];
  const registered = await call(port, 'POST', '/api/auth/register', null, {email: 'p@example.com', password: 'password-p'});
  assert.equal(registered.status, 201, JSON.stringify(registered.body));
  assert.equal((await call(port, 'POST', '/api/auth/register', null, {email: 'q@example.com', password: 'password-q'})).status, 201);
  const tokenP = (await call(port, 'POST', '/api/auth/login', null, {email: 'p@example.com', password: 'password-p'})).body.token;
  const tokenQ = (await call(port, 'POST', '/api/auth/login', null, {email: 'q@example.com', password: 'password-q'})).body.token;

  const create = async (token, requestId, body = {}) => {
    const response = await call(port, 'POST', '/api/transactions', token, {...draft(requestId), ...body});
    assert.ok([200, 201].includes(response.status), `创建失败：${response.status}`);
    return response.body;
  };

  // 未登录、非取消状态和未知记录都不能永久删除。
  assert.equal((await call(port, 'DELETE', '/api/transactions/cancelled', null)).status, 401);
  assert.equal((await call(port, 'DELETE', '/api/transactions/whatever/permanent', null)).status, 401);
  const pending = await create(tokenP, 'p-pending');
  const notCancelled = await call(port, 'DELETE', `/api/transactions/${pending.id}/permanent`, tokenP);
  assert.equal(notCancelled.status, 409);
  assert.match(notCancelled.body.error, /已取消/);
  assert.equal((await call(port, 'DELETE', '/api/transactions/p-missing/permanent', tokenP)).status, 404);

  // 撤销后可以永久删除，记录从列表和磁盘快照中消失。
  assert.equal((await call(port, 'DELETE', `/api/transactions/${pending.id}`, tokenP)).status, 200);
  const permanent = await call(port, 'DELETE', `/api/transactions/${pending.id}/permanent`, tokenP);
  assert.equal(permanent.status, 200);
  assert.deepEqual(permanent.body, {ok: true, id: pending.id});
  assert.equal((await call(port, 'GET', '/api/transactions', tokenP)).body.some(item => item.id === pending.id), false);
  assert.equal((await call(port, 'DELETE', `/api/transactions/${pending.id}/permanent`, tokenP)).status, 404);
  assert.equal(JSON.parse(fs.readFileSync(dbPath, 'utf8')).transactions.some(item => item.id === pending.id), false, '删除后重启服务不应恢复记录');

  // 批量清理只影响当前账号的取消记录，且保持幂等。
  const buy = await create(tokenP, 'p-buy');
  const cancelledSell = await create(tokenP, 'p-sell', {type: 'sell', entryMode: 'shares', amount: 0, shares: 5});
  assert.equal(cancelledSell.status, 'confirmed');
  assert.equal((await call(port, 'DELETE', `/api/transactions/${cancelledSell.id}`, tokenP)).status, 200);
  const survivor = await create(tokenP, 'p-survivor');
  const otherPending = await create(tokenQ, 'q-pending');
  assert.equal((await call(port, 'DELETE', `/api/transactions/${otherPending.id}`, tokenQ)).status, 200);
  const holdingsBefore = (await call(port, 'GET', '/api/holdings', tokenP)).body;

  const cleared = await call(port, 'DELETE', '/api/transactions/cancelled', tokenP);
  assert.equal(cleared.status, 200);
  assert.deepEqual(cleared.body, {ok: true, deleted: 1});
  const remaining = (await call(port, 'GET', '/api/transactions', tokenP)).body;
  assert.deepEqual(remaining.map(item => item.id).sort(), [buy.id, survivor.id].sort());
  assert.equal((await call(port, 'GET', '/api/transactions', tokenQ)).body[0].id, otherPending.id);
  assert.equal((await call(port, 'GET', '/api/transactions', tokenQ)).body[0].status, 'cancelled');
  assert.deepEqual((await call(port, 'GET', '/api/holdings', tokenP)).body, holdingsBefore, '删除已取消交易不应改变持仓');
  assert.deepEqual((await call(port, 'GET', '/api/export', tokenP)).body.data.transactions.map(item => item.id).sort(), [buy.id, survivor.id].sort());
  assert.equal(JSON.parse(fs.readFileSync(dbPath, 'utf8')).transactions.some(item => item.id === cancelledSell.id), false);
  assert.deepEqual((await call(port, 'DELETE', '/api/transactions/cancelled', tokenP)).body, {ok: true, deleted: 0});

  // 跨账号不能永久删除他人记录。
  const qCancelled = await create(tokenQ, 'q-second');
  assert.equal((await call(port, 'DELETE', `/api/transactions/${qCancelled.id}`, tokenQ)).status, 200);
  assert.equal((await call(port, 'DELETE', `/api/transactions/${qCancelled.id}/permanent`, tokenP)).status, 404);
  const foreignClear = await call(port, 'DELETE', '/api/transactions/cancelled', tokenP);
  assert.deepEqual(foreignClear.body, {ok: true, deleted: 0});
  assert.equal((await call(port, 'GET', '/api/transactions', tokenQ)).body.length, 2);
});
