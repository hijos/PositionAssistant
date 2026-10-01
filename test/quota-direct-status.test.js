const { parseDirectPage } = require('../server/quota-sources/fund-manager');
const assert = require('node:assert/strict');
const test = require('node:test');
test('官方暂停申购状态映射为直销额度零', () => {
  const paused = parseDirectPage('<div>申购状态：关闭</div>', { code: '018043', name: '天弘纳斯达克100指数(QDII)A' }, { sourceUrl: 'https://www.thfund.com.cn/fundinfo/018043' });
  assert.equal(paused.channels.direct.status, '暂停申购');
  assert.equal(paused.channels.direct.limit, 0);
  const open = parseDirectPage('<div>申购状态：开放申购</div>', { code: '018043', name: '天弘纳斯达克100指数(QDII)A' }, { sourceUrl: 'https://www.thfund.com.cn/fundinfo/018043' });
  assert.equal(open.channels.direct.status, '开放申购');
  assert.equal(open.channels.direct.limit, null);
});
