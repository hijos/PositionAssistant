const test=require('node:test');
const assert=require('node:assert/strict');
const {ESTIMATION_RULE_VERSION,proxySymbol,normalizeInputs,estimateFromInputs}=require('../server/estimation');

const base={code:'160213',nav:1,navDate:'2026-09-23',qqq:{ratio:1.1},fx:{ratio:1.05}};
test('QQQ and USD/CNY produce deterministic NAV and 100% metadata',()=>{
 const result=estimateFromInputs(base);
 assert.equal(result.estimateRuleVersion,ESTIMATION_RULE_VERSION);
 assert.equal(result.estimatedNav,1.155);
 assert.equal(result.estimateCoverage,1);
 assert.equal(result.holdingsDate,null);
 assert.equal(result.estimateBaseDate,'2026-09-23');
});
test('unsupported rule versions and malformed inputs are rejected',()=>{
 assert.throws(()=>normalizeInputs({...base,ruleVersion:'future-v9'}),/不支持的估算规则版本/);
 assert.throws(()=>normalizeInputs({...base,qqq:null}),/缺少版本化行情输入/);
 assert.throws(()=>estimateFromInputs({...base,fx:null}),/缺少版本化行情输入/);
});
test('selects VOO for S&P 500 funds and QQQ otherwise',()=>{
 assert.equal(proxySymbol('标普500指数基金'), 'VOO');
 assert.equal(proxySymbol('S&P 500 ETF'), 'VOO');
 assert.equal(proxySymbol('纳斯达克100指数'), 'QQQ');
 assert.equal(proxySymbol('全球科技基金'), null);
});
