const headers={'User-Agent':'Mozilla/5.0',Referer:'https://finance.yahoo.com/'};
const ESTIMATION_RULE_VERSION='qqq-fx-v1';
async function get(url){const r=await fetch(url,{headers,signal:AbortSignal.timeout(10000)});if(!r.ok)throw Error('数据接口 HTTP '+r.status);return r.text()}
async function chart(symbol,baseDate){
 const text=await get('https://query1.finance.yahoo.com/v8/finance/chart/'+encodeURIComponent(symbol)+'?interval=1d&period1='+Math.floor(Date.parse(baseDate)/1000-7*86400)+'&period2='+Math.floor(Date.now()/1000+86400));
 const data=JSON.parse(text)?.chart?.result?.[0];if(!data)throw Error('无行情 '+symbol);
 const points=(data.timestamp||[]).map((t,i)=>({date:new Date(t*1000).toLocaleDateString('en-CA',{timeZone:data.meta.exchangeTimezoneName||'America/New_York'}),price:data.indicators.quote[0].close[i],at:t*1000})).filter(x=>x.price>0);
 const base=points.filter(x=>x.date===baseDate).at(-1),last=points.at(-1);
 if(!base||!last||last.date<=baseDate)throw Error('行情缺少基准日或更新价格 '+symbol);
 if(Date.now()-last.at>4*86400000)throw Error('行情已过期 '+symbol);
 return {ratio:last.price/base.price,date:last.date,at:last.at,points,base:base.price};
}
function weightedReturn(qqq,fx){return qqq.ratio*fx.ratio-1}
function normalizeInputs({code,nav,navDate,qqq,fx,ruleVersion=ESTIMATION_RULE_VERSION}){
 if(ruleVersion!==ESTIMATION_RULE_VERSION)throw Error('不支持的估算规则版本');
 if(!/^\d{6}$/.test(String(code))||!(Number(nav)>0)||!/^(\d{4})-(\d{2})-(\d{2})$/.test(String(navDate)))throw Error('估算输入无效');
 if(!qqq||!(Number(qqq.ratio)>0)||!fx||!(Number(fx.ratio)>0))throw Error('缺少版本化行情输入');
 return {ruleVersion,code:String(code),nav:Number(nav),navDate:String(navDate),qqq,fx};
}
function estimateFromInputs(input){
 const x=normalizeInputs(input); const rate=weightedReturn(x.qqq,x.fx);
 return {estimatedNav:Math.round(x.nav*(1+rate)*1e6)/1e6,estimateRuleVersion:x.ruleVersion,estimateCoverage:1,holdingsDate:null,estimateBaseDate:x.navDate,estimateMethod:'按 QQQ + USD/CNY 组合涨跌估算（100%）；不含费用、分红与调仓'};
}
async function estimateUnderlying(code,nav,navDate){
 const sourceUrl='https://finance.yahoo.com/quote/QQQ/';
 const [qqq,fx]=await Promise.all([chart('QQQ',navDate),chart('CNY=X',navDate)]);
 const common=qqq.points.map(p=>p.date).filter(d=>d>navDate&&fx.points.some(q=>q.date===d)).sort().at(-1);
 if(!common)throw Error('缺少同日 QQQ 与汇率行情');
 for(const q of [qqq,fx]){const p=q.points.find(p=>p.date===common);q.ratio=p.price/q.base;q.date=common;q.at=p.at;}
 return {...estimateFromInputs({code,nav,navDate,qqq,fx}),estimateAt:new Date(Math.min(qqq.at,fx.at)).toISOString(),estimateSource:'QQQ + USD/CNY（Yahoo Finance，100%代理）',estimateSourceUrl:sourceUrl};
}
module.exports={ESTIMATION_RULE_VERSION,weightedReturn,normalizeInputs,estimateFromInputs,estimateUnderlying};


