const {test} = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const {installFundRoutes} = require('../server/funds');
test('fund API validates catalog, enforces identity, retries and isolates accounts', async () => {
  const app = express(); app.use(express.json());
  const rows = new Map(); let offline = false;
  installFundRoutes(app, {
    user:req => ({'Bearer a':'alice','Bearer b':'bob'})[req.headers.authorization],
    catalog:{get:async () => {if(offline) throw Error(); return {items:[{code:'000001',name:'基金A',type:'混合型'},{code:'000002',name:'美元基金',type:'QDII'}]};}},
    store:{
      list:async owner => [...rows.values()].filter(x=>x.owner===owner).map(x=>x.fund),
      add:async(owner,fund)=>{const key=owner+fund.code;if(!rows.has(key))rows.set(key,{owner,fund});return rows.get(key).fund;},
      remove:async(owner,code)=>rows.delete(owner+code),
    }
  });
  const server = app.listen(0); await new Promise(resolve=>server.once('listening',resolve));
  const base = `http://127.0.0.1:${server.address().port}/api/my-funds`;
  const request = (token,code) => fetch(base,{method:code===undefined?'GET':'POST',headers:{Authorization:token,'Content-Type':'application/json'},...(code===undefined?{}:{body:JSON.stringify({code,owner_id:'bob',name:'forged'})})});
  try {
    assert.equal((await request('', '000001')).status,401);
    for(const code of ['bad','999999','000002']) assert.equal((await request('Bearer a',code)).status,400);
    const responses=await Promise.all(Array.from({length:8},()=>request('Bearer a','000001')));
    for(const response of responses) assert.equal(response.status,200);
    assert.deepEqual(await (await request('Bearer a')).json(),[{code:'000001',name:'基金A',type:'混合型'}]);
    assert.deepEqual(await (await request('Bearer b')).json(),[]);
    offline=true;
    assert.equal((await request('Bearer a','000001')).status,200);
    assert.equal((await request('Bearer b','000001')).status,503);
    offline=false;
    assert.equal((await request('Bearer b','000001')).status,200);
    assert.equal(rows.size,2);
    assert.equal((await fetch(base+'/000001',{method:'DELETE',headers:{Authorization:'Bearer a'}})).status,204);
    assert.deepEqual(await (await request('Bearer a')).json(),[]);
    assert.equal((await fetch(base+'/000001',{method:'DELETE',headers:{Authorization:'Bearer a'}})).status,404);
    assert.deepEqual(await (await request('Bearer b')).json(),[{code:'000001',name:'基金A',type:'混合型'}]);
  } finally { await new Promise(resolve=>server.close(resolve)); }
});

test('production Bearer parser accepts the issued token and rejects raw tokens', () => {
  const fs = require('node:fs');
  const source = fs.readFileSync(require.resolve('../server/index'), 'utf8');
  const definition = source.slice(source.indexOf('function user(req)'), source.indexOf(String.fromCharCode(10), source.indexOf('function user(req)')));
  const user = new Function('sessions', `${definition}; return user;`)(new Map([['issued-token','alice']]));
  assert.equal(user({headers:{authorization:'Bearer issued-token'}}),'alice');
  assert.equal(user({headers:{authorization:'issued-token'}}),null);
  assert.equal(user({headers:{authorization:'Bearer unknown'}}),null);
});
