const test = require('node:test');
const assert = require('node:assert/strict');
const { directProfileForFund, MANAGER_PROFILES } = require('../server/quota-sources/direct-config');

test('基金公司直销配置按管理人生成官方入口', () => {
  const fortis = directProfileForFund({ code: '012752', name: '华宝纳斯达克100指数(QDII)C人民币' }, 'fortis');
  assert.equal(fortis.managerName, '华宝基金');
  assert.ok(fortis.directUrl.includes('fsfund.com/fund/012752/fundDetail.shtml'));

  const china = directProfileForFund({ code: '000834', name: '华夏纳斯达克100ETF联接(QDII)A' }, 'china-asset');
  assert.equal(china.managerName, '华夏基金');
  assert.match(china.directUrl, /chinaamc\.com\/fund\/000834\/xiaoshouwangdian\.shtml/);
  assert.equal(china.directSourceType, 'fund-manager-page');

  const efund = directProfileForFund({ code: '012752', name: '易方达纳斯达克100指数(QDII)C人民币' }, 'e-fund');
  assert.equal(efund.managerName, '易方达基金');
  const jpmorgan = directProfileForFund({ code: '017641', name: '摩根标普500指数(QDII)人民币A' }, 'jpmorgan');
  assert.equal(jpmorgan.managerName, '摩根基金');
  assert.ok(jpmorgan.directUrl.includes('cifm.com/fund/017641'));
  assert.match(efund.directUrl, /e\.efunds\.com\.cn\/cart\/subscriptions\?form=&fundCode=012752/);

  const guangfa = directProfileForFund({ code: '006479', name: '广发纳斯达克100ETF联接(QDII)C' }, 'guangfa');
  assert.equal(guangfa.managerName, '广发基金');
  assert.ok(guangfa.directUrl.includes('gffunds.com.cn/funds'));

  const guotai = directProfileForFund({ code: '017028', name: '国泰标普500ETF发起联接(QDII)A' }, 'guotai');
  assert.equal(guotai.managerName, '国泰基金');
  assert.ok(guotai.directUrl.includes('e.gtfund.com/etrade/Jijin/view/id/017028'));
  const cmb = directProfileForFund({ code: '019547', name: '招商纳斯达克100ETF发起式联接(QDII)A' }, 'cmbchina');
  assert.equal(cmb.managerName, '招商基金');
  assert.ok(cmb.directUrl.includes('cmfchina.com/web/fundDetail/019547'));

  const bosera = directProfileForFund({ code: '006075', name: '博时标普500ETF联接C' }, 'bosera');
  const ccb = directProfileForFund({ code: '539001', name: '建信纳斯达克100指数(QDII)A人民币' }, 'ccbfund');
  assert.equal(ccb.managerName, '建信基金');
  assert.ok(ccb.directUrl.includes('amcfortune.com/funds/public/539001/index.shtml'));
  const fullgoal = directProfileForFund({ code: '018966', name: '汇添富纳斯达克100ETF发起式联接(QDII)A' }, 'fullgoal');
  assert.equal(fullgoal.managerName, '汇添富基金');
  assert.ok(fullgoal.directUrl.includes('99fund.com/main/products/pofund/018966'));
  const harvest = directProfileForFund({ code: '016532', name: '嘉实纳斯达克100ETF发起联接(QDII)A' }, 'harvest');
  assert.equal(harvest.managerName, '嘉实基金');
  assert.ok(harvest.directUrl.includes('jsfund.cn/main/fund/016532'));
  assert.equal(bosera.managerName, '博时基金');
  assert.ok(bosera.directUrl.includes('bosera.com/corp/fund/006075.html'));

  const dacheng = directProfileForFund({ code: '020369', name: '大成纳斯达克100指数(QDII)' }, 'dacheng');
  assert.equal(dacheng.managerName, '大成基金');
  assert.ok(dacheng.directUrl.includes('dcfund.com.cn/main/fund/productdetail/index.shtml?product_code=020369'));
  const huaan = directProfileForFund({ code: '040001', name: '华安纳斯达克100指数(QDII)' }, 'huaan');
  assert.equal(huaan.managerName, '华安基金');
  assert.ok(huaan.directUrl.includes('huaan.com.cn/funds/040001/index.shtml'));
  const wanjia = directProfileForFund({ code: '019441', name: '万家纳斯达克100指数发起式(QDII)A' }, 'wanjia');
  assert.equal(wanjia.managerName, '万家基金');
  assert.ok(wanjia.directUrl.includes('wjasset.com/products/qdii/019441/index.html'));
  const baoying = directProfileForFund({ code: '008303', name: '宝盈纳斯达克100指数(QDII)' }, 'baoying');
  assert.equal(baoying.managerName, '宝盈基金');
  assert.ok(baoying.directUrl.includes('byfunds.com/fundDetail/008303/index.html'));

    const southern = directProfileForFund({ code: '021000', name: '南方纳斯达克100指数发起(QDII)I' }, 'southern');
  assert.equal(southern.managerName, '南方基金');
  assert.match(southern.directUrl, /nffund\.com\/new\/personal-financing\/detail\.html\?fundCode=021000/);
});

test('建信和天弘仍保持待配置状态', () => {
  assert.equal(directProfileForFund({ code: '018043', name: '天弘纳斯达克100指数(QDII)A' }, 'tianhong'), null);
  assert.equal(MANAGER_PROFILES.tianhong.buildUrl('018043'), 'https://www.thfund.com.cn/fundinfo/018043');
  assert.equal(directProfileForFund({ code: '018043', name: '天弘纳斯达克100指数(QDII)A' }, 'tianhong'), null);
  assert.equal(MANAGER_PROFILES.tianhong.buildUrl('018043'), 'https://www.thfund.com.cn/fundinfo/018043');
  assert.ok(MANAGER_PROFILES['china-asset']);
  assert.ok(MANAGER_PROFILES['e-fund']);
});








