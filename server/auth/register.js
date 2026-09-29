const {hashPassword}=require('./password');
function normalizeEmail(email){return typeof email==='string'?email.trim().toLowerCase():''}
function validateRegistration(email,password){const e=normalizeEmail(email);if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e))throw new Error('邮箱格式无效');if(typeof password!=='string'||password.length<8)throw new Error('密码至少需要 8 个字符');return {email:e,passwordHash:hashPassword(password)}}
module.exports={normalizeEmail,validateRegistration};
