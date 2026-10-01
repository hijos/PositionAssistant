const MANAGER_PROFILES = Object.freeze({
  fortis: { name: '华宝基金', buildUrl: code => `https://www.fsfund.com/fund/${code}/fundDetail.shtml`, source: '华宝基金官方产品详情页', sourceType: 'fund-manager-page', platform: 'fund-company-web' },
  'china-asset': { name: '华夏基金', buildUrl: code => `https://www.chinaamc.com/fund/${code}/xiaoshouwangdian.shtml?source=click`, source: '华夏基金产品页/直销机构信息', sourceType: 'fund-manager-page', platform: 'fund-company-web' },
  'e-fund': { name: '易方达基金', buildUrl: code => `https://e.efunds.com.cn/cart/subscriptions?form=&fundCode=${code}`, source: '易方达基金网上交易购买页', sourceType: 'fund-manager-page', platform: 'fund-company-web' },
  jpmorgan: { name: '摩根基金', buildUrl: code => `https://www.cifm.com/fund/${code}/`, source: '摩根基金产品页/直销信息', sourceType: 'fund-manager-page', platform: 'fund-company-web' },
  guangfa: { name: '广发基金', buildUrl: code => `https://www.gffunds.com.cn/funds/?fromSearch=1&fundcode=${code}`, source: '广发基金官方产品页', sourceType: 'fund-manager-page', platform: 'fund-company-web' },
  guotai: { name: '国泰基金', buildUrl: code => `https://e.gtfund.com/etrade/Jijin/view/id/${code}`, source: '国泰基金官方产品详情页', sourceType: 'fund-manager-page', platform: 'fund-company-web' },
  cmbchina: { name: '招商基金', buildUrl: code => `https://www.cmfchina.com/web/fundDetail/${code}/`, source: '招商基金官方产品详情页', sourceType: 'fund-manager-page', platform: 'fund-company-web' },
  bosera: { name: '博时基金', buildUrl: code => `https://www.bosera.com/corp/fund/${code}.html`, source: '博时基金官方产品页', sourceType: 'fund-manager-page', platform: 'fund-company-web' },
  ccbfund: { name: '建信基金', buildUrl: code => `https://www.amcfortune.com/funds/public/${code}/index.shtml`, source: '建信基金官方产品详情页', sourceType: 'fund-manager-page', platform: 'fund-company-web' },
  tianhong: { name: '天弘基金', buildUrl: code => `https://www.thfund.com.cn/fundinfo/${code}`, source: '天弘基金官方产品页（当前受 WAF 保护）', sourceType: 'fund-manager-page', platform: 'fund-company-web', enabled: false },
  fullgoal: { name: '汇添富基金', buildUrl: code => `https://www.99fund.com/main/products/pofund/${code}/fundnav.shtml`, source: '汇添富基金官方产品页', sourceType: 'fund-manager-page', platform: 'fund-company-web' },
  harvest: { name: '嘉实基金', buildUrl: code => `https://www.jsfund.cn/main/fund/${code}/fundManager.shtml`, source: '嘉实基金官方产品页', sourceType: 'fund-manager-page', platform: 'fund-company-web' },
  southern: { name: '南方基金', buildUrl: code => `https://www.nffund.com/new/personal-financing/detail.html?fundCode=${code}`, source: '南方基金产品详情页/直销信息', sourceType: 'fund-manager-page', platform: 'fund-company-web' },
  dacheng: { name: '大成基金', buildUrl: code => `https://www.dcfund.com.cn/main/fund/productdetail/index.shtml?product_code=${code}`, source: '大成基金官方产品详情页', sourceType: 'fund-manager-page', platform: 'fund-company-web' },
  huaan: { name: '华安基金', buildUrl: code => `https://www.huaan.com.cn/funds/${code}/index.shtml`, source: '华安基金官方产品详情页', sourceType: 'fund-manager-page', platform: 'fund-company-web' },
  wanjia: { name: '万家基金', buildUrl: code => `https://www.wjasset.com/products/qdii/${code}/index.html`, source: '万家基金官方产品详情页', sourceType: 'fund-manager-page', platform: 'fund-company-web' },
  baoying: { name: '宝盈基金', buildUrl: code => `https://www.byfunds.com/fundDetail/${code}/index.html`, source: '宝盈基金官方产品详情页', sourceType: 'fund-manager-page', platform: 'fund-company-web' }
});
function directProfileForFund(fund, managerCode) { const profile = MANAGER_PROFILES[managerCode]; if (!profile || profile.enabled === false || !fund?.code) return null; return { managerCode, managerName: profile.name, directUrl: profile.buildUrl(fund.code), directSource: profile.source, directSourceType: profile.sourceType, directPlatform: profile.platform, directApi: managerCode === 'southern' ? 'southern-subscription-status' : null }; }
module.exports = { MANAGER_PROFILES, directProfileForFund };
