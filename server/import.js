const IMPORT_FORMAT = 'position-assistant.export';
const IMPORT_VERSION = 1;
const COLLECTIONS = ['funds', 'transactions', 'plans', 'planEntries', 'quotaOverrides'];

function isRecord(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function assertImportPackage(value) {
  if (!isRecord(value)) throw new Error('导入文件必须是 JSON 对象');
  if (value.format !== IMPORT_FORMAT) throw new Error('导入文件格式不支持');
  if (value.version !== IMPORT_VERSION) throw new Error('导入文件版本不支持');
  if (typeof value.exportedAt !== 'string' || !Number.isFinite(Date.parse(value.exportedAt))) {
    throw new Error('导出时间无效');
  }
  if (!isRecord(value.data)) throw new Error('导入文件缺少 data 数据');
  for (const collection of COLLECTIONS) {
    if (!Array.isArray(value.data[collection])) throw new Error(`data.${collection} 必须是数组`);
    if (value.data[collection].some(item => !isRecord(item))) {
      throw new Error(`data.${collection} 只能包含 JSON 对象`);
    }
  }
  return value;
}

function countBy(items, field) {
  return items.reduce((counts, item) => {
    const key = item[field] == null || item[field] === '' ? 'unknown' : String(item[field]);
    counts[key] = (counts[key] || 0) + 1;
    return counts;
  }, {});
}

function summarizeImportPackage(value) {
  const pkg = assertImportPackage(value);
  const { data } = pkg;
  const counts = Object.fromEntries(COLLECTIONS.map(name => [name, data[name].length]));
  counts.total = COLLECTIONS.reduce((total, name) => total + counts[name], 0);
  const fundCodes = new Set();
  for (const collection of COLLECTIONS) {
    for (const item of data[collection]) {
      if (typeof item.code === 'string' && item.code.trim()) fundCodes.add(item.code.trim());
      if (typeof item.fundCode === 'string' && item.fundCode.trim()) fundCodes.add(item.fundCode.trim());
    }
  }
  return {
    format: pkg.format,
    version: pkg.version,
    exportedAt: pkg.exportedAt,
    counts,
    fundCodes: [...fundCodes].sort(),
    transactionStatuses: countBy(data.transactions, 'status'),
    planEntryStatuses: countBy(data.planEntries, 'status')
  };
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function assertUnique(items, collection) {
  const ids = new Set();
  for (const item of items) {
    const id = item.id == null ? '' : String(item.id);
    if (!id || ids.has(id)) throw new Error(`${collection} 包含重复或无效主键`);
    ids.add(id);
  }
}

function replaceAccountData(db, ownerId, value) {
  const pkg = assertImportPackage(value);
  const data = pkg.data;
  for (const collection of ['transactions', 'plans', 'planEntries']) assertUnique(data[collection], collection);
  const fundCodes = new Set();
  for (const item of data.funds) {
    const code = String(item.code || '').trim();
    if (!/^\d{6}$/.test(code) || fundCodes.has(code)) throw new Error('funds 包含重复或无效基金代码');
    fundCodes.add(code);
  }
  const planIds = new Set(data.plans.map(item => String(item.id)));
  for (const entry of data.planEntries) {
    if (!entry.planId || !planIds.has(String(entry.planId))) throw new Error('planEntries 包含不存在的计划引用');
  }
  const quotaCodes = new Set();
  for (const item of data.quotaOverrides) {
    const code = String(item.code || '').trim();
    if (!/^\d{6}$/.test(code) || quotaCodes.has(code)) throw new Error('quotaOverrides 包含重复或无效基金代码');
    quotaCodes.add(code);
  }
  const next = clone(db);
  const owned = name => (next[name] || []).filter(item => item.userId !== ownerId);
  next.transactions = owned('transactions').concat(data.transactions.map(item => ({ ...clone(item), userId: ownerId })));
  next.plans = owned('plans').concat(data.plans.map(item => ({ ...clone(item), userId: ownerId })));
  next.planEntries = owned('planEntries').concat(data.planEntries.map(item => ({ ...clone(item), userId: ownerId })));
  next.quotas = (next.quotas || []).filter(item => !(item.userOverride === true && item.userId === ownerId))
    .concat(data.quotaOverrides.map(item => ({ ...clone(item), userId: ownerId, userOverride: true, valueSource: 'user', priority: 'user' })));
  const importedCodes = new Set(data.funds.map(item => String(item.code || '').trim()).filter(Boolean));
  next.funds = (next.funds || []).filter(item => item.userId !== ownerId && (item.userId || !importedCodes.has(String(item.code || '').trim())))
    .concat(data.funds.map(item => ({ ...clone(item), userId: ownerId })));
  return next;
}

module.exports = { COLLECTIONS, IMPORT_FORMAT, IMPORT_VERSION, assertImportPackage, validateImportPackage: assertImportPackage, summarizeImportPackage, replaceAccountData };
