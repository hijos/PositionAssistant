const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const sourcePath = path.join(root, 'quota-service', 'data', 'db.json');
const mainPath = path.join(root, 'data', 'db.json');
const seedPath = path.join(root, 'client', 'assets', 'quota_seed.json');
const emptySeed = { version: 0, quotas: [] };

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function findArrayEnd(text, start) {
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let i = start; i < text.length; i += 1) {
    const char = text[i];
    if (inString) {
      if (escaped) escaped = false;
      else if (char === '\\') escaped = true;
      else if (char === '"') inString = false;
      continue;
    }
    if (char === '"') {
      inString = true;
    } else if (char === '[') {
      depth += 1;
    } else if (char === ']') {
      depth -= 1;
      if (depth === 0) return i + 1;
    }
  }
  throw new Error('quotas 数组未闭合');
}

function replaceMainQuotas(quotas) {
  const text = fs.readFileSync(mainPath, 'utf8');
  const keyPosition = text.indexOf('"quotas"');
  if (keyPosition < 0) throw new Error('主数据文件缺少 quotas 字段');
  const arrayStart = text.indexOf('[', keyPosition);
  if (arrayStart < 0) throw new Error('主数据文件缺少 quotas 数组');
  const arrayEnd = findArrayEnd(text, arrayStart);
  const newline = text.includes('\r\n') ? '\r\n' : '\n';
  let serialized = JSON.stringify(quotas, null, 2).replace(/\n/g, '\n  ');
  if (newline === '\r\n') serialized = serialized.replace(/\n/g, '\r\n');
  fs.writeFileSync(
    mainPath,
    text.slice(0, arrayStart) + serialized + text.slice(arrayEnd),
    'utf8',
  );
}

function writeSeed(seed) {
  fs.mkdirSync(path.dirname(seedPath), { recursive: true });
  fs.writeFileSync(seedPath, `${JSON.stringify(seed, null, 2)}\n`, 'utf8');
}

function prepare() {
  const source = readJson(sourcePath);
  if (!Array.isArray(source.quotas) || source.quotas.length === 0) {
    throw new Error('额度子服务数据没有可用 quotas');
  }
  const codes = source.quotas.map((item) => item?.code).filter(Boolean);
  if (new Set(codes).size !== codes.length) throw new Error('额度数据存在重复基金代码');
  replaceMainQuotas(source.quotas);
  writeSeed({
    version: source.version ?? null,
    updatedAt: source.quotas
      .map((item) => item.updatedAt)
      .filter(Boolean)
      .sort()
      .at(-1) ?? null,
    quotas: source.quotas,
  });
  console.log(`synced ${source.quotas.length} quotas (version ${source.version ?? 'unknown'})`);
}

if (process.argv[2] === '--clear-seed') {
  writeSeed(emptySeed);
  console.log('cleared bundled quota seed');
} else {
  prepare();
}
