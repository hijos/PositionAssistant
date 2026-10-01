const test=require('node:test');
const assert=require('node:assert/strict');
const {parseSouthernLimit,normalizeSouthernRecord,createSouthernSource}=require('../server/quota-sources/southern');

test('南方官方状态备注按直销口径解析限额',()=>{
  assert.equal(parseSouthernLimit('自2026年7月21日起，本基金I类份额的大额申购（含定投和转换转入）限额调整为200元。'),200);
  const item=normalizeSouthernRecord({fundCode:'021000',fundName:'南方纳斯达克100指数发起（QDII）I',sgStatus:'1',remark:'自2026年7月21日起，本基金I类份额的大额申购限额调整为200元。'},{code:'021000',name:'南方纳斯达克100指数发起(QDII)I',category:'纳斯达克100',managerCode:'southern'},'https://www.nffund.com/new/transaction-guide/product-status-and-limits.html');
  assert.equal(item.channels.direct.status,'开放申购');
  assert.equal(item.channels.direct.limit,200);
  assert.equal(item.officialRestriction.limit,200);
  assert.equal(item.officialRestriction.channelScope,'fund-manager-official-default-direct');
});

test('南方接口适配器只按基金代码取官方记录',async()=>{
  const source=createSouthernSource({fetchImpl:async()=>new Response(JSON.stringify({code:'ETS-5BP00000',data:{fundlist:[{fundCode:'021000',fundName:'南方纳斯达克100指数发起（QDII）I',sgStatus:'1',remark:'直销渠道开放申购，限额200元'}]}}),{status:200})});
  const item=await source.fetch({code:'021000',name:'南方纳斯达克100指数发起(QDII)I',category:'纳斯达克100',managerCode:'southern'});
  assert.equal(item.channels.direct.status,'开放申购');
  assert.equal(item.channels.direct.limit,200);
});


test('南方暂停申购状态映射为直销额度零', () => {
  const item = normalizeSouthernRecord({fundCode:'021000', fundName:'南方纳斯达克100指数发起（QDII）I', sgStatus:'0', remark:'暂停申购'}, {code:'021000', name:'南方纳斯达克100指数发起(QDII)I', category:'纳斯达克100', managerCode:'southern'}, 'https://www.nffund.com/new/transaction-guide/product-status-and-limits.html');
  assert.equal(item.channels.direct.status, '暂停申购');
  assert.equal(item.channels.direct.limit, 0);
});
