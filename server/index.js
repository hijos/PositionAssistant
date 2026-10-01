const {estimateUnderlying,proxySymbol}=require('./estimation'); const {validateRegistration}=require('./auth/register'); const {verifyPassword}=require('./auth/password'); const express=require('express'); const {calculate,holdings,dailyFormalReturns}=require('./accounting'); const {addCalendarDays,eligibleNavStartDate,selectNextNavDate}=require('./trading-date');
const fs=require('fs'); const path=require('path'); const https=require('https'); const crypto=require('node:crypto'); const app=express(); app.use(express.json()); const sessions=new Map();
const dbPath=process.env.POSITIONASSISTANT_DB_PATH||path.join(__dirname,'../data/db.json');
const seed={users:[],funds:[{code:'160213',name:'国泰纳斯达克100指数',nav:4.419},{code:'021000',name:'南方纳斯达克100指数发起',nav:1}],transactions:[{id:'t1',userId:'demo',fundCode:'160213',type:'buy',amount:100,shares:22.63,fee:0,date:'2026-09-01',status:'confirmed'}],plans:[],quotas:[],fundCatalog:[]};
function load(){try{return JSON.parse(fs.readFileSync(dbPath,'utf8'))}catch{fs.mkdirSync(path.dirname(dbPath),{recursive:true});fs.writeFileSync(dbPath,JSON.stringify(seed,null,2));return seed}} let db=load(); function save(){fs.writeFileSync(dbPath,JSON.stringify(db,null,2))} function uid(){return Math.random().toString(36).slice(2,10)} function user(req){const match=String(req.headers.authorization||'').match(/^Bearer\s+(.+)$/i);return match ? sessions.get(match[1].trim())||null : null}
async function history(code, startDate, endDate) {
 const url=new URL('https://api.fund.eastmoney.com/f10/lsjz');
 url.search=new URLSearchParams({fundCode:code,pageIndex:'1',pageSize:'100',...(startDate?{startDate,endDate:endDate||addCalendarDays(startDate,32)}:{})});
 const r=await fetch(url,{headers:{Referer:'https://fund.eastmoney.com/'},signal:AbortSignal.timeout(10000)});
 if(!r.ok)throw Error('净值接口 '+r.status);const body=await r.json();
 if(!Array.isArray(body?.Data?.LSJZList))throw Error('净值响应无效');
 return body.Data.LSJZList.filter(x=>Number(x.DWJZ)>0).map(x=>({nav:Number(x.DWJZ),navDate:x.FSRQ}));
}
async function fetchNav(code){
 const [official,estimate]=await Promise.allSettled([history(code),fetch('https://fundgz.1234567.com.cn/js/'+code+'.js',{signal:AbortSignal.timeout(8000)}).then(r=>r.text()).then(t=>JSON.parse(t.match(/jsonpgz\((\{.*\})\)/)?.[1]||'null'))]);
 const old=db.funds.find(f=>f.code===code)||{};const x=estimate.status==='fulfilled'?estimate.value:null;
 const n=official.status==='fulfilled'?official.value[0]:null;
 if(!n)throw Error('正式净值暂时无法更新');
 let underlying=null,estimateError=null;try{underlying=await estimateUnderlying(code,n.nav,n.navDate,old.name||x?.name||'')}catch(e){estimateError=e.message}
 return {...n,code,name:old.name||(db.fundCatalog||[]).find(f=>f.code===code)?.name||x?.name||code,source:'东方财富历史净值',sourceType:'official',sourceError:null,updatedAt:new Date().toISOString(),estimatedNav:proxySymbol(old.name||x?.name||'')&&x?.jzrq===n.navDate&&Number(x.gsz)>0?Number(x.gsz):null,estimateAt:proxySymbol(old.name||x?.name||'')?x?.gztime?.replace(' ','T')||null:null,estimateSource:proxySymbol(old.name||x?.name||'')?'东方财富第三方估值（非底层持仓自算）':null,estimateError,...underlying};
}
function validateTrade(b){
 if(!/^\d{6}$/.test(b.fundCode)||!['buy','sell'].includes(b.type)||!['amount','shares','holding'].includes(b.entryMode)||!['before','after'].includes(b.cutoff))throw Error('交易参数无效');
 if(b.entryMode==='holding'&&b.type!=='buy')throw Error('持有金额录入仅支持买入');
 if(!/^\d{4}-\d{2}-\d{2}$/.test(b.date)||!Number.isFinite(Date.parse(b.date))||new Date(b.date).toISOString().slice(0,10)!==b.date||b.date>new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Shanghai'}))throw Error('交易日期无效');
 const rawValue=Number(b.entryMode==='holding'?b.holdingAmount:b[b.entryMode]);if(!Number.isFinite(rawValue)||rawValue<=0)throw Error('金额或份额必须大于0');
 const value=Math.round((rawValue+Number.EPSILON)*100)/100;if(value<=0)throw Error('金额或份额最小精度为0.01');
 const holdingProfit=b.entryMode==='holding'?Number(b.holdingProfit):0;
 if(b.entryMode==='holding'&&(b.holdingProfit==null||String(b.holdingProfit).trim()===''||!Number.isFinite(holdingProfit)||holdingProfit>=value))throw Error('持有收益必须是有效金额且小于持有金额');
 const requestedMode=b.entryMode==='holding'?'fixed':(b.feeMode==null?(b.fixedFee!=null||b.fee!=null?'fixed':'rate'):String(b.feeMode));
 if(!['rate','fixed'].includes(requestedMode))throw Error('手续费模式无效');
 let feeRate=null,fixedFee=0;
 if(requestedMode==='rate'){
  if(b.fixedFee!=null&&Number(b.fixedFee)!==0)throw Error('手续费率和固定手续费只能二选一');
  feeRate=b.feeRate==null?0:Number(b.feeRate);
  if(!Number.isFinite(feeRate)||feeRate<0||feeRate>=100)throw Error('手续费率必须在0至100%之间');
 }else{
  if(b.feeRate!=null&&Number(b.feeRate)!==0)throw Error('手续费率和固定手续费只能二选一');
  fixedFee=Number(b.fixedFee??b.fee??0);
  if(!Number.isFinite(fixedFee)||fixedFee<0)throw Error('固定手续费必须是非负数字');
  fixedFee=Math.round((fixedFee+Number.EPSILON)*100)/100;
 }
 const text=(value,max)=>{if(value==null)return '';if(typeof value!=='string'||value.trim().length>max)throw Error('交易备注或来源无效');return value.trim()};
 const clientRequestId=b.clientRequestId==null?'':text(b.clientRequestId,128);
 return {fundCode:b.fundCode,fundName:text(b.fundName,200),fundType:text(b.fundType,100),type:b.type,entryMode:b.entryMode,amount:b.entryMode==='amount'?value:0,shares:b.entryMode==='shares'?value:0,holdingAmount:b.entryMode==='holding'?value:null,holdingProfit:b.entryMode==='holding'?holdingProfit:null,feeMode:requestedMode,feeRate, fixedFee,date:b.date,cutoff:b.cutoff,note:text(b.note,200),source:text(b.source,100),clientRequestId,status:'pending'};
}
function validatePlan(body={}) {
 const fundCode=String(body.fundCode||'').trim();
 if(!/^\d{6}$/.test(fundCode)) throw Error('基金代码无效');
 const fundName=String(body.fundName||'').trim();
 if(fundName.length>200) throw Error('基金名称无效');
 const mode=body.mode==null ? (body.shares!=null ? 'shares' : 'amount') : String(body.mode);
 if(!['amount','shares'].includes(mode)) throw Error('定投方式无效');
 const value=Number(body[mode]);
 if(!Number.isFinite(value)||value<=0) throw Error('定投金额或份额必须大于0');
 const cycle=String(body.cycle||'monthly');
 if(!['weekly','monthly'].includes(cycle)) throw Error('定投周期无效');
 const executionDay=Number(body.executionDay); const maxDay=cycle==='weekly'?7:31;
 if(!Number.isInteger(executionDay)||executionDay<1||executionDay>maxDay) throw Error('执行日无效');
 const startDate=String(body.startDate||'');
 if(!/^\d{4}-\d{2}-\d{2}$/.test(startDate)||!Number.isFinite(Date.parse(startDate))||new Date(startDate).toISOString().slice(0,10)!==startDate) throw Error('起始日期无效');
 const note=body.note==null?'':String(body.note).trim(); if(note.length>200) throw Error('备注无效');
 return {fundCode,fundName,mode,amount:mode==='amount'?Math.round(value*100)/100:null,shares:mode==='shares'?Math.round(value*10000)/10000:null,cycle,startDate,executionDay,enabled:body.enabled!==false,note};
}
function applyConfirmedNav(transaction){
 if(transaction.status!=='confirmed'||!(Number(transaction.tradeNav)>0)||!transaction.navDate)return;
 const fund=db.funds.find(item=>item.code===transaction.fundCode);
 if(fund){Object.assign(fund,{nav:Number(transaction.tradeNav),navDate:transaction.navDate,source:fund.source||'交易确认正式净值',sourceType:fund.sourceType||'official'});return}
 db.funds.push({code:transaction.fundCode,name:transaction.fundName||transaction.fundCode,nav:Number(transaction.tradeNav),navDate:transaction.navDate,source:'交易确认正式净值',sourceType:'official'});
}
async function settle(t){
 const date=eligibleNavStartDate(t.date,t.cutoff);
 try {
  const rows=(await history(t.fundCode,date)).sort((a,b)=>a.navDate.localeCompare(b.navDate));
  const navDate=selectNextNavDate(t.date,t.cutoff,rows);
  const n=rows.find(row=>row.navDate===navDate);
  if(n)return {...calculate(t,n.nav),navDate:n.navDate};
  return {...t,status:'pending',pendingReason:'对应交易日正式净值尚未公布，公布后自动计算份额'};
 }catch{return {...t,status:'pending',pendingReason:'净值来源暂时不可用，请稍后重试确认'};}
}
const catalogService=require('./catalog').configuredCatalogService();
const quotaRules=require('./quotas'); const {createQuotaCollector}=require('./quota-sources'); const {directProfileForFund}=require('./quota-sources/direct-config');
const {exportPackage}=require('./export'); const {summarizeImportPackage,replaceAccountData}=require('./import');
async function getFundCatalog(){const snapshot=await catalogService.get();db.fundCatalog=snapshot.items;return snapshot.items}
app.get('/api/fund-catalog',require('./catalog/route').catalogHandler(catalogService));
// F14 formal official NAV snapshots are served from the PostgreSQL cache.
// Keep the legacy JSON accounting endpoints below for transactions and estimates.
require('./nav').installNavRoutes(app, require('./nav').configuredNavService());
// F26 index quotes and FX rates are served from the PostgreSQL market snapshot cache.
require('./market').installMarketRoutes(app, require('./market').configuredMarketService());
// 部分基金页面只展示“限大额”，具体数值由基金公司销售页面/公告披露；在这里维护已核验的补充值。
const supplementalQuotaLimits={
 '021000':{limit:200,source:'南方基金限额公告',sourceType:'fund-manager-announcement',sourceUrl:'https://www.9fzt.com/detail/fund_021000_2_10777974.html'}
}
const quotaCollector=createQuotaCollector({ supplemental: supplementalQuotaLimits });
async function fetchFundQuota(fund, category){
 const enriched={...fund,category, ...directProfileForFund(fund,quotaRules.managerCode(fund))};
 const collected=await quotaCollector.collect(enriched);
 const distribution=collected.results.find(item=>item.channels?.distribution);
 const direct=collected.results.find(item=>item.channels?.direct);
 if(!distribution&&!direct) throw Error(collected.errors.map(item=>item.error).join('; ')||'no quota source');
 const base=distribution||direct;
 return quotaRules.normalizeQuota({...base, channels:{...(distribution?.channels||{}),...(direct?.channels||{})}, preferredChannel:quotaRules.preferredChannel({...(distribution?.channels||{}),...(direct?.channels||{})}), sourceErrors:collected.errors});
}
async function refreshQuotas(ownerId=null){
 const catalog=await getFundCatalog(); const candidates=catalog.filter(quotaRules.isCandidate).slice(0,80);
 const settled=await Promise.allSettled(candidates.map(f=>fetchFundQuota(f,quotaRules.classifyFund(f.name))));
 const fresh=settled.filter(x=>x.status==='fulfilled').map(x=>x.value).filter(x=>x.status!=='场内交易'&&!/美元|美钞|美汇/.test(x.name));
 if(!fresh.length) throw Error('no quota records');
 db.quotas=quotaRules.mergeAutomaticQuotas(fresh,db.quotas||[]); save();
 const visible=quotaRules.visibleQuotas(db.quotas||[],ownerId);
 return {items:visible,summary:{updated:fresh.length,distributionUpdated:fresh.filter(x=>x.channels?.distribution).length,directUpdated:fresh.filter(x=>x.channels?.direct).length,directUnavailable:fresh.filter(x=>!x.channels?.direct).length,failed:settled.filter(x=>x.status==='rejected').length}};
}app.post('/api/auth/register',(req,res)=>{try{const {email,passwordHash}=validateRegistration(req.body?.email,req.body?.password);if(db.users.some(x=>x.email===email))return res.status(409).json({error:'email exists'});const u={id:uid(),email,passwordHash};db.users.push(u);save();res.status(201).json({id:u.id,email:u.email})}catch(e){res.status(400).json({error:e.message})}});app.post('/api/auth/login',(req,res)=>{const email=String(req.body?.email||'').trim().toLowerCase();const u=db.users.find(x=>x.email===email);if(!u||!verifyPassword(req.body?.password,u.passwordHash))return res.status(401).json({error:'invalid credentials'});const token=crypto.randomBytes(32).toString('base64url');sessions.set(token,u.id);res.json({token,userId:u.id,email:u.email})});app.post('/api/auth/logout',(req,res)=>{const match=String(req.headers.authorization||'').match(/^Bearer\s+(.+)$/i);if(match)sessions.delete(match[1].trim());res.status(204).end()});
require('./funds').installFundRoutes(app,{user,catalog:catalogService,store:require('./funds').configuredFundStore()});
app.get('/api/funds/search',require('./catalog/search').searchHandler(catalogService));
app.post('/api/quotas/refresh',async(req,res)=>{try{const result=await refreshQuotas(user(req));res.json({...result,source:'多渠道额度来源',updatedAt:new Date().toISOString()})}catch(e){res.status(502).json({error:'额度数据源暂时不可用',detail:e.message,items:quotaRules.visibleQuotas(db.quotas||[],user(req))})}});
app.get('/api/funds',async(req,res)=>{for(const f of db.funds){if(!f.name)f.name=(db.fundCatalog||[]).find(x=>x.code===f.code)?.name||f.code}const refresh=req.query.refresh==='1';if(refresh){for(const f of db.funds){try{const latest=await fetchNav(f.code);Object.assign(f,latest);if(!f.name)f.name=(db.fundCatalog||[]).find(x=>x.code===f.code)?.name||f.code}catch(e){f.source=f.source||'缓存数据';f.sourceType='cached';f.sourceError='暂时无法更新';f.updatedAt=f.updatedAt||null}}save()}res.json(db.funds)});
app.get('/api/funds/:code/nav',async(req,res)=>{try{const n=await fetchNav(req.params.code);const f=db.funds.find(x=>x.code===req.params.code);if(f){Object.assign(f,n);if(!f.name)f.name=(db.fundCatalog||[]).find(x=>x.code===f.code)?.name||f.code}else db.funds.push(n);save();res.json(n)}catch(e){res.status(502).json({error:'基金数据源暂时不可用',detail:e.message})}});
app.use('/api/transactions',(req,res,next)=>{if(!user(req))return res.sendStatus(401);next()});app.use('/api/plans',(req,res,next)=>{if(!user(req))return res.sendStatus(401);next()});app.use('/api/holdings',(req,res,next)=>{if(!user(req))return res.sendStatus(401);next()});app.get('/api/transactions',(req,res)=>res.json(db.transactions.filter(t=>t.userId===user(req))));
app.post('/api/transactions/preview',async(req,res)=>{try{res.json(await settle(validateTrade(req.body||{})))}catch(e){res.status(400).json({error:e.message})}});
const createLocks=new Map();
async function withCreateLock(key, action){
 const previous=createLocks.get(key)||Promise.resolve();
 let release;
 const current=new Promise(resolve=>{release=resolve});
 createLocks.set(key,current);
 await previous;
 try{return await action()}finally{release();if(createLocks.get(key)===current)createLocks.delete(key)}
}
app.post('/api/transactions',async(req,res)=>{try{
 const ownerId=user(req); const draft=validateTrade(req.body||{});
 const key=draft.clientRequestId?`${ownerId}:${draft.clientRequestId}`:null;
 const create=async()=>{
  if(key){const existing=db.transactions.find(x=>x.userId===ownerId&&x.clientRequestId===draft.clientRequestId);if(existing)return {record:existing,duplicate:true}}
  const t=await settle({...draft,id:uid(),userId:ownerId});
  holdings([...db.transactions.filter(x=>x.userId===ownerId),t],db.funds);
  if(!db.funds.some(f=>f.code===t.fundCode)){try{db.funds.push(await fetchNav(t.fundCode))}catch{db.funds.push({code:t.fundCode,name:(db.fundCatalog||[]).find(f=>f.code===t.fundCode)?.name||t.fundCode})}}
  applyConfirmedNav(t);db.transactions.push(t);save();return {record:t,duplicate:false};
 };
 const result=key?await withCreateLock(key,create):await create();
 res.status(result.duplicate?200:201).json(result.record);
}catch(e){res.status(400).json({error:e.message})}});
const confirming=new Map();
function confirmPending(ownerId=null){
 const key=ownerId||'*';
 if(confirming.has(key))return confirming.get(key);
 const pending=(async()=>{
  const confirmed=[];
  for(const old of db.transactions.filter(t=>t.status==='pending'&&(!ownerId||t.userId===ownerId))){const t=await settle(old);if(old.status!=='pending'||t.status!=='confirmed')continue;
  try{holdings(db.transactions.filter(x=>x.userId===old.userId).map(x=>x.id===old.id?t:x),db.funds);Object.assign(old,t);applyConfirmedNav(old);confirmed.push(old)}catch(e){old.pendingReason=e.message}}
  save();return confirmed;
 })().finally(()=>{confirming.delete(key)});
 confirming.set(key,pending);
 return pending;
}
app.post('/api/transactions/confirm',async(req,res)=>{try{res.json({ok:true,transactions:await confirmPending(user(req))})}catch(e){res.status(409).json({error:e.message})}});
app.delete('/api/transactions/cancelled',(req,res)=>{const ownerId=user(req);
 const removed=db.transactions.filter(t=>t.userId===ownerId&&t.status==='cancelled');
 if(!removed.length)return res.json({ok:true,deleted:0});
 const ids=new Set(removed.map(t=>t.id));db.transactions=db.transactions.filter(t=>!ids.has(t.id));save();res.json({ok:true,deleted:removed.length})});
app.delete('/api/transactions/:id/permanent',(req,res)=>{const t=db.transactions.find(t=>t.id===req.params.id&&t.userId===user(req));
 if(!t)return res.status(404).json({error:'记录不存在'});
 if(t.status!=='cancelled')return res.status(409).json({error:'只能删除已取消交易，请先撤销该交易'});
 db.transactions=db.transactions.filter(x=>x.id!==t.id);save();res.json({ok:true,id:t.id})});
app.delete('/api/transactions/:id',(req,res)=>{const t=db.transactions.find(t=>t.id===req.params.id&&t.userId===user(req));if(!t)return res.status(404).json({error:'记录不存在'});
 if(t.status==='cancelled')return res.json(t);
 try{holdings(db.transactions.filter(x=>x.userId===user(req)&&x.id!==t.id),db.funds);t.status='cancelled';t.cancelledAt=new Date().toISOString();save();res.json(t)}catch(e){res.status(409).json({error:e.message})}});
app.get('/api/holdings',(req,res)=>{try{res.json(holdings(db.transactions.filter(t=>t.userId===user(req)),db.funds))}catch(e){res.status(409).json({error:e.message})}});
app.get('/api/daily-returns',async(req,res)=>{
 const ownerId=user(req); if(!ownerId)return res.status(401).json({error:'需要登录'});
 try {
  const transactions=db.transactions.filter(t=>t.userId===ownerId);
  const codes=[...new Set(transactions.filter(t=>t.status==='confirmed').map(t=>t.fundCode))];
  const histories=await Promise.all(codes.map(async code=>[code,await history(code)]));
  const rows=dailyFormalReturns(transactions,Object.fromEntries(histories));
  const grouped=new Map();
  for(const row of rows){
   const item=grouped.get(row.navDate)||{navDate:row.navDate,marketValue:0,previousMarketValue:0,cashFlow:0,profit:0,funds:[]};
   item.marketValue+=row.marketValue; item.previousMarketValue+=row.previousMarketValue; item.cashFlow+=row.cashFlow; item.profit+=row.profit;
   item.funds.push(row); grouped.set(row.navDate,item);
  }
  res.json({items:[...grouped.values()].sort((a,b)=>a.navDate.localeCompare(b.navDate)).map(item=>({...item,marketValue:Math.round(item.marketValue*100)/100,previousMarketValue:Math.round(item.previousMarketValue*100)/100,cashFlow:Math.round(item.cashFlow*100)/100,profit:Math.round(item.profit*100)/100}))});
 } catch(e) { res.status(502).json({error:'每日正式收益暂时不可用'}); }
});
setInterval(()=>confirmPending().catch(console.error),300000).unref();
function validPlanDate(plan,date){if(!/^\d{4}-\d{2}-\d{2}$/.test(date)||new Date(date).toISOString().slice(0,10)!==date||date<plan.startDate)return false;const d=new Date(date+'T00:00:00Z');return plan.cycle==='weekly'?((d.getUTCDay()||7)===plan.executionDay):d.getUTCDate()===plan.executionDay}
app.get('/api/plans',(req,res)=>res.json(db.plans.filter(x=>x.userId===user(req))));app.post('/api/plans',(req,res)=>{try{const p={...validatePlan(req.body),id:uid(),userId:user(req),createdAt:new Date().toISOString()};db.plans.push(p);save();res.status(201).json(p)}catch(e){res.status(400).json({error:e.message})}});app.put('/api/plans/:id',(req,res)=>{const p=db.plans.find(x=>x.id===req.params.id&&x.userId===user(req));if(!p)return res.sendStatus(404);try{Object.assign(p,validatePlan({...p,...req.body}));save();res.json(p)}catch(e){res.status(400).json({error:e.message})}});app.patch('/api/plans/:id/status',(req,res)=>{const p=db.plans.find(x=>x.id===req.params.id&&x.userId===user(req));if(!p)return res.sendStatus(404);if(typeof req.body?.enabled!=='boolean')return res.status(400).json({error:'enabled必须是布尔值'});p.enabled=req.body.enabled;save();res.json(p)});app.post('/api/plans/:id/enable',(req,res)=>{const p=db.plans.find(x=>x.id===req.params.id&&x.userId===user(req));if(!p)return res.sendStatus(404);p.enabled=true;save();res.json(p)});app.post('/api/plans/:id/pause',(req,res)=>{const p=db.plans.find(x=>x.id===req.params.id&&x.userId===user(req));if(!p)return res.sendStatus(404);p.enabled=false;save();res.json(p)});
app.get('/api/plans/:id/entries',(req,res)=>{const p=db.plans.find(x=>x.id===req.params.id&&x.userId===user(req));if(!p)return res.sendStatus(404);res.json((db.planEntries||[]).filter(x=>x.planId===p.id&&x.userId===user(req)))});
app.post('/api/plans/:id/entries/generate',(req,res)=>{const ownerId=user(req);const p=db.plans.find(x=>x.id===req.params.id&&x.userId===ownerId);if(!p)return res.sendStatus(404);if(!p.enabled)return res.status(409).json({error:'定投计划已暂停'});const scheduledDate=String(req.body?.scheduledDate||'');if(!validPlanDate(p,scheduledDate))return res.status(400).json({error:'执行日期与计划不匹配'});if(!Array.isArray(db.planEntries))db.planEntries=[];const key=ownerId+':'+p.id+':'+scheduledDate;const existing=db.planEntries.find(x=>x.dedupeKey===key);if(existing)return res.status(200).json(existing);const entry={id:uid(),dedupeKey:key,planId:p.id,userId:ownerId,fundCode:p.fundCode,fundName:p.fundName,mode:p.mode,amount:p.amount,shares:p.shares,scheduledDate,status:'pending',transactionId:null,createdAt:new Date().toISOString()};db.planEntries.push(entry);save();res.status(201).json(entry)});
function createPlanEntry(ownerId,p,body,{requireEnabled=true}={}){if(requireEnabled&&!p.enabled)throw Object.assign(Error('定投计划已暂停'),{status:409});const scheduledDate=String(body?.scheduledDate||'');if(!validPlanDate(p,scheduledDate))throw Object.assign(Error('执行日期与计划不匹配'),{status:400});if(!Array.isArray(db.planEntries))db.planEntries=[];const key=ownerId+':'+p.id+':'+scheduledDate;const existing=db.planEntries.find(x=>x.dedupeKey===key);if(existing)return {entry:existing,created:false};const entry={id:uid(),dedupeKey:key,planId:p.id,userId:ownerId,fundCode:p.fundCode,fundName:p.fundName,mode:p.mode,amount:p.amount,shares:p.shares,scheduledDate,status:'pending',transactionId:null,createdAt:new Date().toISOString()};db.planEntries.push(entry);return {entry,created:true}}
app.post('/api/plans/:id/entries/supplement',(req,res)=>{const ownerId=user(req);const p=db.plans.find(x=>x.id===req.params.id&&x.userId===ownerId);if(!p)return res.sendStatus(404);try{const out=createPlanEntry(ownerId,p,req.body,{requireEnabled:false});save();res.status(out.created?201:200).json(out.entry)}catch(e){res.status(e.status||400).json({error:e.message})}});
app.put('/api/plans/:id/entries/:entryId',(req,res)=>{const ownerId=user(req);const p=db.plans.find(x=>x.id===req.params.id&&x.userId===ownerId);if(!p)return res.sendStatus(404);const entry=(db.planEntries||[]).find(x=>x.id===req.params.entryId&&x.planId===p.id&&x.userId===ownerId);if(!entry)return res.sendStatus(404);if(entry.status!=='pending')return res.status(409).json({error:'仅待确认的一期定投可修改'});try{const date=String(req.body?.scheduledDate||entry.scheduledDate);if(!validPlanDate(p,date))throw Error('执行日期与计划不匹配');const duplicate=(db.planEntries||[]).find(x=>x.id!==entry.id&&x.dedupeKey===ownerId+':'+p.id+':'+date);if(duplicate)return res.status(409).json({error:'该执行日期已有定投记录'});entry.scheduledDate=date;entry.dedupeKey=ownerId+':'+p.id+':'+date;if(req.body?.note!=null){const note=String(req.body.note).trim();if(note.length>200)throw Error('备注无效');entry.note=note}save();res.json(entry)}catch(e){if(e.status)return res.status(e.status).json({error:e.message});res.status(400).json({error:e.message})}});
app.post('/api/plans/:id/entries/:entryId/skip',(req,res)=>{const ownerId=user(req);const p=db.plans.find(x=>x.id===req.params.id&&x.userId===ownerId);if(!p)return res.sendStatus(404);const entry=(db.planEntries||[]).find(x=>x.id===req.params.entryId&&x.planId===p.id&&x.userId===ownerId);if(!entry)return res.sendStatus(404);if(entry.status==='skipped')return res.json(entry);if(entry.status!=='pending')return res.status(409).json({error:'仅待确认的一期定投可跳过'});const note=req.body?.note==null?'':String(req.body.note).trim();if(note.length>200)return res.status(400).json({error:'备注无效'});entry.status='skipped';entry.skippedAt=new Date().toISOString();if(note)entry.skipNote=note;save();res.json(entry)});app.post('/api/plans/:id/entries/:entryId/confirm',async(req,res)=>{const ownerId=user(req);const p=db.plans.find(x=>x.id===req.params.id&&x.userId===ownerId);if(!p)return res.sendStatus(404);const entry=(db.planEntries||[]).find(x=>x.id===req.params.entryId&&x.planId===p.id&&x.userId===ownerId);if(!entry)return res.sendStatus(404);if(entry.status==='confirmed'||entry.status==='pending-confirmation')return res.json(entry);if(entry.status!=='pending')return res.status(409).json({error:'待记账记录状态不可确认'});try{const draft=validateTrade({fundCode:entry.fundCode,fundName:entry.fundName,type:'buy',entryMode:entry.mode,amount:entry.amount,shares:entry.shares,feeMode:'rate',feeRate:0,fixedFee:0,date:entry.scheduledDate,cutoff:'before',note:`定投计划 ${p.id}`,source:'定投确认',clientRequestId:`plan-entry:${entry.id}`});const t=await settle({...draft,id:uid(),userId:ownerId});holdings([...db.transactions.filter(x=>x.userId===ownerId),t],db.funds);if(!db.funds.some(f=>f.code===t.fundCode)){db.funds.push({code:t.fundCode,name:t.fundName||t.fundCode})}applyConfirmedNav(t);db.transactions.push(t);entry.transactionId=t.id;entry.status=t.status==='confirmed'?'confirmed':'pending-confirmation';entry.pendingReason=t.pendingReason||null;entry.confirmedAt=new Date().toISOString();save();res.status(201).json(entry)}catch(e){res.status(400).json({error:e.message})}});
app.use('/api/quotas',(req,res,next)=>{if(!user(req))return res.sendStatus(401);next()});
function quotaForOwner(code, ownerId) {
 const items=quotaRules.visibleQuotas(db.quotas||[],ownerId);
 return items.find(x=>x.code===code)||null;
}
app.get('/api/quotas',(req,res)=>res.json(quotaRules.visibleQuotas(db.quotas||[],user(req)).filter(x=>x.status!=='场内交易')));
app.put('/api/quotas/:code',(req,res)=>{
 const ownerId=user(req); const body=req.body||{};
 const hasStatus=Object.prototype.hasOwnProperty.call(body,'status'); const hasLimit=Object.prototype.hasOwnProperty.call(body,'limit');
 const channel=body.channel==null ? null : String(body.channel);
 const channelFields=body.fields&&typeof body.fields==='object'&&!Array.isArray(body.fields)?body.fields:null;
 if(channel && !['distribution','direct'].includes(channel))return res.status(400).json({error:'channel must be distribution or direct'});
 if(!hasStatus&&!hasLimit&&!channelFields)return res.status(400).json({error:'至少需要修改一项额度字段'});
 let q=(db.quotas||[]).find(x=>x.code===req.params.code&&quotaRules.isUserOverride(x)&&x.userId===ownerId);
 const automatic=(db.quotas||[]).find(x=>x.code===req.params.code&&!quotaRules.isUserOverride(x));
 if(!q&&!automatic)return res.sendStatus(404);
 if(!q){q={...automatic,userId:ownerId,userOverride:true,automaticStatus:automatic.status??null,automaticLimit:automatic.limit??null,overrideFields:[]};db.quotas.push(q)}
 const fields=new Set(Array.isArray(q.overrideFields) ? q.overrideFields : quotaRules.overrideFields(q));
 if(channelFields){
  q.channels=JSON.parse(JSON.stringify(q.channels||automatic?.channels||{})); q.channels[channel]=quotaRules.normalizeChannel({...q.channels[channel],...channelFields},q);
  for(const name of ['status','limit']) if(Object.prototype.hasOwnProperty.call(channelFields,name)) fields.add(`channels.${channel}.${name}`);
 }
 if(hasStatus){if(typeof body.status!=='string'||!body.status.trim()||body.status.trim().length>80)return res.status(400).json({error:'status must be a non-empty string'});q.status=body.status.trim();fields.add('status'); q.channels=JSON.parse(JSON.stringify(q.channels||automatic?.channels||{})); q.channels.distribution=quotaRules.normalizeChannel({...q.channels.distribution,status:q.status},q)}
 if(hasLimit){const limit=body.limit==null?null:Number(body.limit);if(limit!=null&&(!Number.isFinite(limit)||limit<0))return res.status(400).json({error:'limit must be a non-negative number or null'});q.limit=limit;fields.add('limit'); q.channels=JSON.parse(JSON.stringify(q.channels||automatic?.channels||{})); q.channels.distribution=quotaRules.normalizeChannel({...q.channels.distribution,limit},q)}
 Object.assign(q,{userId:ownerId,userOverride:true,overrideFields:[...fields],valueSource:'user',priority:'user'});save();
 res.json(quotaForOwner(req.params.code,ownerId));
});
app.post('/api/quotas/:code/restore',(req,res)=>{
 const ownerId=user(req); const override=(db.quotas||[]).find(x=>x.code===req.params.code&&quotaRules.isUserOverride(x)&&x.userId===ownerId); const automatic=(db.quotas||[]).find(x=>x.code===req.params.code&&!quotaRules.isUserOverride(x)); const target=override||automatic;
 if(!target)return res.sendStatus(404);
 fetchFundQuota(target,target.category||'QDII').then(latest=>{db.quotas=quotaRules.restoreAutomaticQuota(db.quotas||[],latest,ownerId);save();res.json(quotaForOwner(req.params.code,ownerId)||latest)}).catch(e=>res.status(502).json({error:'额度自动数据暂时不可用',detail:e.message}))
});
app.get('/api/export',(req,res)=>{const ownerId=user(req);if(!ownerId)return res.status(401).json({error:'需要登录'});res.json(exportPackage(db,ownerId));});
app.post('/api/import/preview',(req,res)=>{if(!user(req))return res.status(401).json({error:'需要登录'});try{const summary=summarizeImportPackage(req.body);res.json({valid:true,format:summary.format,version:summary.version,exportedAt:summary.exportedAt,summary});}catch(e){res.status(400).json({valid:false,error:e.message})}});
app.post('/api/import',(req,res)=>{const ownerId=user(req);if(!ownerId)return res.status(401).json({error:'需要登录'});try{const next=replaceAccountData(db,ownerId,req.body);fs.writeFileSync(dbPath,JSON.stringify(next,null,2));db=next;res.json({ok:true,summary:summarizeImportPackage(req.body)});}catch(e){res.status(400).json({ok:false,error:e.message})}});
app.use(express.static(path.join(__dirname,'../web')));if(require.main===module)app.listen(process.env.PORT||3000,()=>console.log('PositionAssistant listening')); module.exports={app,validateTrade,validatePlan,settle,history,confirmPending,exportPackage,summarizeImportPackage};




