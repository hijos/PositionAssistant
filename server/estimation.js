const headers={'User-Agent':'Mozilla/5.0',Referer:'https://fundf10.eastmoney.com/'};
const ESTIMATION_RULE_VERSION='us-equity-weighted-fx-v1';
async function get(url){const r=await fetch(url,{headers,signal:AbortSignal.timeout(10000)});if(!r.ok)throw Error('数据接口 HTTP '+r.status);return r.text()}
function parseHoldings(text){
 const date=text.replace(/<[^>]+>/g,'').match(/截止至[：:]?\s*(\d{4}-\d{2}-\d{2})/)?.[1];
 const table=text.match(/<tbody>([\s\S]*?)<\/tbody>/i)?.[1]||text.match(/<table[^>]*>([\s\S]*?)<\/table>/i)?.[1]||'';
 const rows=[...table.matchAll(/<tr[^>]*>([\s\S]*?)<\/tr>/gi)].flatMap(m=>{const symbol=m[1].match(/(?:105|106|107)\.([A-Z][A-Z0-9.-]*)/)?.[1];const weight=m[1].match(/([\d.]+)%/)?.[1];return symbol&&weight?[{symbol,weight:Number(weight)/100}]:[]});
 if(!date||!rows.length)throw Error('未取得可识别的美股持仓');return {date,rows};
}
async function chart(symbol,baseDate){
 const text=await get('https://query1.finance.yahoo.com/v8/finance/chart/'+encodeURIComponent(symbol)+'?interval=1d&period1='+Math.floor(Date.parse(baseDate)/1000-7*86400)+'&period2='+Math.floor(Date.now()/1000+86400));
 const data=JSON.parse(text)?.chart?.result?.[0];if(!data)throw Error('无行情 '+symbol);
 const points=(data.timestamp||[]).map((t,i)=>({date:new Date(t*1000).toLocaleDateString('en-CA',{timeZone:data.meta.exchangeTimezoneName||'America/New_York'}),price:data.indicators.quote[0].close[i],at:t*1000})).filter(x=>x.price>0);
 const base=points.filter(x=>x.date===baseDate).at(-1),last=points.at(-1);
 if(!base||!last||last.date<=baseDate)throw Error('行情缺少基准日或更新价格 '+symbol);
 if(Date.now()-last.at>4*86400000)throw Error('行情已过期 '+symbol);
 return {ratio:last.price/base.price,date:last.date,at:last.at,points,base:base.price};
}
function weightedReturn(rows,quotes,fx){return rows.reduce((sum,r,i)=>sum+r.weight*(quotes[i].ratio*fx.ratio-1),0)}
function normalizeInputs({code,nav,navDate,holdings,quotes,fx,ruleVersion=ESTIMATION_RULE_VERSION}){
 if(ruleVersion!==ESTIMATION_RULE_VERSION)throw Error('不支持的估算规则版本');
 if(!/^\d{6}$/.test(String(code))||!(Number(nav)>0)||!/^(\d{4})-(\d{2})-(\d{2})$/.test(String(navDate)))throw Error('估算输入无效');
 if(!holdings?.date||!Array.isArray(holdings.rows)||!holdings.rows.length)throw Error('缺少版本化持仓输入');
 const rows=holdings.rows.map(r=>({symbol:String(r.symbol),weight:Number(r.weight)}));
 if(rows.some(r=>!/^[A-Z][A-Z0-9.-]*$/.test(r.symbol)||!Number.isFinite(r.weight)||r.weight<=0)||rows.reduce((s,r)=>s+r.weight,0)>1.01)throw Error('持仓权重无效');
 return {ruleVersion,code:String(code),nav:Number(nav),navDate:String(navDate),holdings:{date:holdings.date,rows},quotes,fx};
}
function estimateFromInputs(input){
 const x=normalizeInputs(input); const coverage=x.holdings.rows.reduce((s,r)=>s+r.weight,0);
 if(!x.quotes||!x.fx)throw Error('缺少版本化行情输入');
 const rate=weightedReturn(x.holdings.rows,x.quotes,x.fx);
 return {estimatedNav:Math.round(x.nav*(1+rate)*1e6)/1e6,estimateRuleVersion:x.ruleVersion,estimateCoverage:coverage,holdingsDate:x.holdings.date,estimateBaseDate:x.navDate,estimateMethod:'已披露美股按权重估算并叠加 USD/CNY；未覆盖资产收益按0；不含费用、分红与调仓'};
}
async function estimateUnderlying(code,nav,navDate){
 const sourceUrl='https://fundf10.eastmoney.com/FundArchivesDatas.aspx?type=jjcc&code='+code+'&topline=10';
 const report=parseHoldings(await get(sourceUrl));if(Date.now()-Date.parse(report.date)>200*86400000)throw Error('持仓披露超过200天');
 const coverage=report.rows.reduce((s,r)=>s+r.weight,0);if(coverage<=0||coverage>1.01)throw Error('持仓权重无效');
 const [quotes,fx]=await Promise.all([Promise.all(report.rows.map(r=>chart(r.symbol,navDate))),chart('CNY=X',navDate)]);
 const common=quotes[0].points.map(p=>p.date).filter(d=>d>navDate&&[...quotes,fx].every(q=>q.points.some(p=>p.date===d))).sort().at(-1);if(!common)throw Error('缺少同日美股与汇率行情');for(const q of [...quotes,fx]){const p=q.points.find(p=>p.date===common);q.ratio=p.price/q.base;q.date=p.date;q.at=p.at;}
 const rate=weightedReturn(report.rows,quotes,fx);
 return {...estimateFromInputs({code,nav,navDate,holdings:report,quotes,fx}),estimateAt:new Date(Math.min(...quotes.map(q=>q.at),fx.at)).toISOString(),estimateSource:'披露美股持仓加权 + USD/CNY（Yahoo Finance）',estimateSourceUrl:sourceUrl};
}
module.exports={ESTIMATION_RULE_VERSION,parseHoldings,weightedReturn,normalizeInputs,estimateFromInputs,estimateUnderlying};



