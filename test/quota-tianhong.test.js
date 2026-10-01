const test = require('node:test');
const assert = require('node:assert/strict');
const { parseDirectPage } = require('../server/quota-sources/fund-manager');

test('天弘官方页面关闭申购映射为直销额度零', () => {
  const item = parseDirectPage('<div>基金代码：018043</div><div>申购状态：关闭</div><div>赎回状态：开放</div>', { code: '018043', name: '天弘纳斯达克100指数发起（QDII）A' }, { sourceUrl: 'https://www.thfund.com.cn/fundinfo/018043' });
  assert.equal(item.channels.direct.status, '暂停申购');
  assert.equal(item.channels.direct.limit, 0);
  assert.equal(item.channels.direct.sourceUrl, 'https://www.thfund.com.cn/fundinfo/018043');
});
