const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const sourcePath = process.env.QUOTA_SOURCE_DB_PATH
  ? path.resolve(process.env.QUOTA_SOURCE_DB_PATH)
  : path.join(root, 'quota-service', 'data', 'db.json');
const seedPath = process.env.QUOTA_SEED_PATH
  ? path.resolve(process.env.QUOTA_SEED_PATH)
  : path.join(root, 'quota-service', 'seed.json');

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function validateQuotas(quotas) {
  if (!Array.isArray(quotas) || quotas.length === 0) {
    throw new Error('quota seed must contain a non-empty quotas array');
  }
  const codes = quotas.map((item) => String(item?.code || ''));
  if (codes.some((code) => !/^\d{6}$/.test(code))) {
    throw new Error('quota seed contains an invalid fund code');
  }
  if (new Set(codes).size !== codes.length) {
    throw new Error('quota seed contains duplicate fund codes');
  }
}

function createSeed(source) {
  validateQuotas(source.quotas);
  const quotas = source.quotas.map(({ consensus, ...quota }) => quota);
  return {
    schemaVersion: Number.isInteger(source.schemaVersion) ? source.schemaVersion : 1,
    version: Number.isInteger(source.version) ? source.version : 0,
    settings: { ...(source.settings || {}) },
    quotas,
    corrections: [],
    audit: [],
  };
}

function validateSeed(seed) {
  validateQuotas(seed.quotas);
  if (!Array.isArray(seed.corrections) || seed.corrections.length !== 0) {
    throw new Error('quota seed must not contain correction history');
  }
  if (!Array.isArray(seed.audit) || seed.audit.length !== 0) {
    throw new Error('quota seed must not contain audit history');
  }
}

if (process.argv[2] === '--check') {
  const seed = readJson(seedPath);
  validateSeed(seed);
  console.log(`validated ${seed.quotas.length} quota records in ${path.relative(root, seedPath)}`);
} else {
  const seed = createSeed(readJson(sourcePath));
  fs.mkdirSync(path.dirname(seedPath), { recursive: true });
  fs.writeFileSync(seedPath, `${JSON.stringify(seed, null, 2)}\n`, 'utf8');
  console.log(`wrote ${seed.quotas.length} quota records to ${path.relative(root, seedPath)}`);
}
