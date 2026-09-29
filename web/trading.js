const oldRender=render;
const htmlEscape=value=>String(value??'—').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const transactionStatus=value=>value==='confirmed'?'已确认':value==='cancelled'?'已取消':'待确认';
const transactionType=value=>value==='buy'?'买入':'卖出';

async function showHoldingDetail(code){
  try{
    const [holdings,transactions,funds]=await Promise.all([api('/api/holdings'),api('/api/transactions'),api('/api/funds')]);
    const holding=holdings.find(item=>item.fundCode===code);
    if(!holding){app.innerHTML='<div class="card"><div class="empty">持仓不存在或已清空</div><button class="btn" onclick="render(\'holdings\')">返回持仓</button></div>';return}
    const fund=(funds||[]).find(item=>item.code===code);
    const related=transactions.filter(item=>item.fundCode===code);
    app.innerHTML=`<div class="card span-12"><div style="display:flex;justify-content:space-between;align-items:center;gap:12px"><div><h2>${htmlEscape(holding.fundName||fund?.name||code)}</h2><div class="small">${htmlEscape(code)}</div></div><button class="btn" onclick="render('holdings')">返回持仓</button></div><div class="grid" style="margin-top:18px"><div class="card span-4"><div class="label">当前份额</div><div class="value">${money(holding.shares)} 份</div></div><div class="card span-4"><div class="label">剩余持仓成本</div><div class="value">¥${money(holding.cost)}</div></div><div class="card span-4"><div class="label">正式市值</div><div class="value">${formalMoney(holding.marketValue)}</div></div><div class="card span-4"><div class="label">累计投入</div><div class="value">¥${money(holding.invested)}</div></div><div class="card span-4"><div class="label">累计赎回</div><div class="value">¥${money(holding.redeemed)}</div></div><div class="card span-4"><div class="label">正式持有收益</div><div class="value">${formalMoney(holding.profit)}</div></div><div class="card span-4"><div class="label">正式收益率</div><div class="value">${formalRate(holding.profitRate)}</div></div><div class="card span-4"><div class="label">正式净值</div><div class="value">${holding.nav==null?'—':money(holding.nav)}</div><div class="small">净值日期 ${htmlEscape(holding.navDate||'—')}</div></div><div class="card span-4"><div class="label">已实现收益</div><div class="value">¥${money(holding.realizedProfit)}</div></div></div></div><div class="card span-12"><h2>关联交易（${related.length}）</h2>${related.length?`<table><thead><tr><th>日期</th><th>方向</th><th>金额</th><th>份额</th><th>净值日期</th><th>状态</th></tr></thead><tbody>${related.map(t=>`<tr><td>${htmlEscape(t.date||'—')}<div class="small">${t.cutoff==='after'?'15:00 后':'15:00 前'}</div></td><td>${transactionType(t.type)}</td><td>${t.entryMode==='shares'?'—':'¥'+money(t.amount)}</td><td>${money(t.shares)}</td><td>${htmlEscape(t.navDate||'—')}</td><td>${transactionStatus(t.status)}${t.status==='pending'?`<div class="small">${htmlEscape(t.pendingReason||'等待正式净值')}</div>`:''}</td></tr>`).join('')}</tbody></table>`:'<div class="empty">暂无关联交易</div>'}</div>`;
  }catch(error){app.innerHTML=`<div class="card"><div class="empty">持仓详情读取失败：${htmlEscape(error.message)}</div><button class="btn" onclick="render('holdings')">返回持仓</button></div>`}
}

render=async function(page='holdings'){
  await oldRender(page);
  if(page==='transactions'){
    const ts=await api('/api/transactions');
    const table=app.querySelector('table');
    table.querySelector('thead tr').insertAdjacentHTML('beforeend','<th>操作</th>');
    table.querySelectorAll('tbody tr').forEach((row,i)=>{
      const t=ts[i];
      row.cells[4].textContent=t.status==='pending'?'待计算':money(t.shares);
      const feeLabel=t.feeMode==='fixed'?'固定费用':t.feeRate==null?'历史费用':t.feeRate+'%';
      row.cells[5].textContent=feeLabel+' · '+money(t.fee)+' 元';
      row.cells[7].textContent=t.status==='cancelled'?'已撤销':t.status==='confirmed'?'已确认 · '+(t.navDate||t.date):'待确认 · '+(t.pendingReason||'等待查询净值');
      const cell=row.insertCell();
      if(t.status!=='cancelled'){
        const button=document.createElement('button');button.className='btn';button.textContent='撤销';
        button.onclick=async()=>{button.disabled=true;try{await api('/api/transactions/'+encodeURIComponent(t.id),{method:'DELETE'});await render('transactions')}catch(e){button.textContent=e.message;button.disabled=false}};
        cell.append(button);
      }
    });
    const retry=document.createElement('button');retry.className='btn';retry.textContent='重新确认待确认交易';
    retry.onclick=async()=>{retry.disabled=true;try{await api('/api/transactions/confirm',{method:'POST'});await render('transactions')}catch(e){retry.textContent=e.message;retry.disabled=false}};
    table.before(retry);
  }
  if(page==='holdings'){
    const hs=await api('/api/holdings');
    app.querySelectorAll('.row').forEach((row,i)=>{
      const x=hs[i],details=row.lastElementChild;details.innerHTML='';
      for(const text of ['正式市值：'+(x.marketValue==null?'暂无正式净值':'¥'+money(x.marketValue)),'正式持有收益：'+(x.profit==null?'暂无正式净值':'¥'+money(x.profit))+' · '+(x.navDate||'—'),'预估持有收益：'+(x.estimatedProfit==null?'暂无有效预估':'¥'+money(x.estimatedProfit)),x.estimatedProfit==null?'':x.estimateSource+' · '+x.estimateAt,x.estimateCoverage==null?'':'披露持仓覆盖 '+(x.estimateCoverage*100).toFixed(2)+'% · 披露日 '+x.holdingsDate,x.estimateMethod||'',x.estimatedProfit==null?(x.estimateError||''):'','已实现收益：¥'+money(x.realizedProfit)]){
        if(text){const p=document.createElement('div');p.className='small';p.textContent=text;details.append(p)}
      }
      const button=document.createElement('button');button.className='btn';button.type='button';button.textContent='查看详情';button.onclick=()=>showHoldingDetail(x.fundCode);details.append(button);
    });
  }
};

let previewVersion=0,previewTimer;
function tradeBody(){const feeMode=document.querySelector('#fFeeMode').value;const fee=Number(document.querySelector('#fFee').value||0);return {fundCode:document.querySelector('#fCode').value,type:document.querySelector('#fType').value,entryMode:document.querySelector('#fMode').value,amount:Number(document.querySelector('#fAmount').value),shares:Number(document.querySelector('#fAmount').value),feeMode,feeRate:feeMode==='rate'?fee:null,fixedFee:feeMode==='fixed'?fee:null,date:document.querySelector('#fDate').value,cutoff:document.querySelector('#fCutoff').value}}
function toggleFeeMode(){const mode=document.querySelector('#fFeeMode').value;document.querySelector('#fFeeLabel').textContent=mode==='rate'?'手续费率（%，可选，默认0）':'固定手续费（元，可选，默认0）';document.querySelector('#fFee').step=mode==='rate'?'0.0001':'0.01';document.querySelector('#fFee').placeholder=mode==='rate'?'例如0.15表示0.15%':'例如1.50';previewTrade()}
function previewTrade(){const version=++previewVersion;clearTimeout(previewTimer);const box=document.querySelector('#tradePreview');if(!box)return;box.textContent='正在查询对应日期正式净值…';previewTimer=setTimeout(async()=>{try{const t=await api('/api/transactions/preview',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(tradeBody())});if(version!==previewVersion||!box.isConnected)return;box.textContent=t.status==='confirmed'?'成交净值 '+t.tradeNav+'（'+t.navDate+'） · 自动计算 '+money(t.shares)+' 份 · 手续费 '+money(t.fee)+' 元':t.pendingReason}catch(e){if(version===previewVersion)box.textContent=e.message}},350)}
const oldChoose=chooseFund;chooseFund=function(code,name){oldChoose(code,name);previewTrade()};
addTransaction=function(){
  app.innerHTML='<div class="card"><h2>记录买入 / 卖出</h2><form id="tradeForm"><div class="field"><label>基金</label>'+fundPicker()+'</div><div class="field"><label>操作</label><select id="fType"><option value="buy">买入 / 加仓</option><option value="sell">卖出 / 减仓</option></select></div><div class="field"><label>填写方式</label><select id="fMode"><option value="amount">金额（元，买入含手续费；卖出为扣费前金额）</option><option value="shares">份额</option></select></div><div class="field"><label>金额 / 份额</label><input id="fAmount" type="number" step="0.01" min="0.01" required></div><div class="field"><label>手续费类型</label><select id="fFeeMode" onchange="toggleFeeMode()"><option value="rate">按费率</option><option value="fixed">固定费用</option></select></div><div class="field"><label id="fFeeLabel">手续费率（%，可选，默认0）</label><input id="fFee" type="number" step="0.0001" min="0" max="99.9999" placeholder="例如0.15表示0.15%"></div><div class="field"><label>交易日期</label><input id="fDate" type="date" required value="'+new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Shanghai'})+'"></div><div class="field"><label>交易时间（北京时间）</label><select id="fCutoff"><option value="before">15:00 前</option><option value="after">15:00 后（含15:00）</option></select></div><p id="tradePreview" role="status">选择基金并填写金额后自动计算份额。</p><p class="small">按日期及15:00分界后的首个公布净值日计算，特殊休市日请核对成交单。</p><button class="btn primary" type="submit">保存交易</button> <button class="btn" type="button" onclick="render()">返回持仓</button></form></div>';
  const form=document.querySelector('#tradeForm');form.addEventListener('input',previewTrade);form.addEventListener('change',previewTrade);form.onsubmit=async e=>{e.preventDefault();const button=form.querySelector('[type=submit]');button.disabled=true;try{await api('/api/transactions',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(tradeBody())});await render('transactions')}catch(e){document.querySelector('#tradePreview').textContent=e.message}finally{button.disabled=false}};
};
render();
