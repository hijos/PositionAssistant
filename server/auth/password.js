const crypto=require('node:crypto');
const N=16384,r=8,p=1,keylen=64;
function hashPassword(password){if(typeof password!=='string'||password.length<8)throw new Error('密码至少需要 8 个字符');const salt=crypto.randomBytes(16);const hash=crypto.scryptSync(password,salt,keylen,{N,r,p});return `scrypt$${N}$${r}$${p}$${salt.toString('base64url')}$${hash.toString('base64url')}`}
function verifyPassword(password,encoded){try{const [,n,rr,pp,s,h]=encoded.split('$');const hash=crypto.scryptSync(password,Buffer.from(s,'base64url'),keylen,{N:+n,r:+rr,p:+pp});return crypto.timingSafeEqual(hash,Buffer.from(h,'base64url'))}catch{return false}}
module.exports={hashPassword,verifyPassword};
