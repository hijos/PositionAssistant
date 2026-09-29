const test=require('node:test');
const assert=require('node:assert/strict');
const {ESTIMATION_RULE_VERSION,normalizeInputs,estimateFromInputs}=require('../server/estimation');

const base={code:'160213',nav:1,navDate:'2026-09-23',holdings:{date:'2026-06-30',rows:[{symbol:'AAPL',weight:.6},{symbol:'MSFT',weight:.2}]},quotes:[{ratio:1.1},{ratio:.9}],fx:{ratio:1.05}};
test('versioned estimation inputs produce deterministic NAV and metadata',()=>{
 const result=estimateFromInputs(base);
 assert.equal(result.estimateRuleVersion,ESTIMATION_RULE_VERSION);
 assert.equal(result.estimatedNav,1.082);
 assert.equal(result.estimateCoverage,.8);
 assert.equal(result.estimateBaseDate,'2026-09-23');
});
test('unsupported rule versions and malformed inputs are rejected',()=>{
 assert.throws(()=>normalizeInputs({...base,ruleVersion:'future-v9'}),/不支持的估算规则版本/);
 assert.throws(()=>normalizeInputs({...base,holdings:{...base.holdings,rows:[{symbol:'bad symbol',weight:.2}]}}),/持仓权重无效/);
 assert.throws(()=>estimateFromInputs({...base,quotes:null}),/缺少版本化行情输入/);
});
