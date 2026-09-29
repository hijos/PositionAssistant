const EXPORT_VERSION = 1;

function exportPackage(db, ownerId, now = new Date().toISOString()) {
  const transactions = (db.transactions || []).filter(item => item.userId === ownerId).map(({ userId, ...item }) => item);
  const fundCodes = new Set(transactions.map(item => item.fundCode));
  const funds = (db.funds || []).filter(item => (!item.userId || item.userId === ownerId) && (!item.code || fundCodes.has(item.code))).map(({ userId, ...item }) => item);
  const plans = (db.plans || []).filter(item => item.userId === ownerId).map(({ userId, ...item }) => item);
  const planIds = new Set(plans.map(item => item.id));
  const planEntries = (db.planEntries || []).filter(item => item.userId === ownerId && planIds.has(item.planId)).map(({ userId, ...item }) => item);
  const quotas = (db.quotas || []).filter(item => item.userOverride === true && item.userId === ownerId).map(({ userId, ...item }) => item);
  return {
    format: 'position-assistant.export',
    version: EXPORT_VERSION,
    exportedAt: now,
    data: { funds, transactions, plans, planEntries, quotaOverrides: quotas }
  };
}

module.exports = { EXPORT_VERSION, exportPackage };
