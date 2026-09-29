import 'dart:convert';

import 'repository.dart';
import 'import_repository.dart';
import 'nav_repository.dart';

bool _validDate(String date) {
  final parsed = DateTime.tryParse(date);
  return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) &&
      parsed != null && parsed.toIso8601String().substring(0, 10) == date;
}

class LocalPlanRepository {
  LocalPlanRepository(this.open);
  final Future<Repository> Function() open;

  Future<List<Map<String, dynamic>>> list() async =>
      (await open()).list('plans');

  Future<Map<String, dynamic>> create({
    required String fundCode,
    required String fundName,
    required String mode,
    required double value,
    required String cycle,
    required String startDate,
    required int executionDay,
  }) async {
    if (!RegExp(r'^\d{6}$').hasMatch(fundCode) || fundName.trim().isEmpty) {
      throw const FormatException('基金信息无效');
    }
    if (!['amount', 'shares'].contains(mode) || !value.isFinite || value < 0.01) {
      throw const FormatException('定投金额或份额必须大于0');
    }
    if (!['weekly', 'monthly'].contains(cycle) ||
        executionDay < 1 ||
        executionDay > (cycle == 'weekly' ? 7 : 31) ||
        !_validDate(startDate)) {
      throw const FormatException('定投周期或日期无效');
    }
    final record = <String, dynamic>{
      'id': 'local-plan-${DateTime.now().microsecondsSinceEpoch}',
      'fundCode': fundCode,
      'fundName': fundName.trim(),
      'mode': mode,
      'amount': mode == 'amount' ? value : 0,
      'shares': mode == 'shares' ? value : 0,
      'cycle': cycle,
      'startDate': startDate,
      'executionDay': executionDay,
      'enabled': true,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    final storage = await open();
    await storage.put('plans', record['id'] as String, record);
    return record;
  }

  Future<Map<String, dynamic>> setEnabled(
    String id,
    bool enabled,
  ) async {
    final storage = await open();
    final plan = await storage.get('plans', id);
    if (plan == null) throw const FormatException('定投计划不存在');
    final next = {...plan, 'enabled': enabled};
    await storage.put('plans', id, next);
    return next;
  }

  Future<List<Map<String, dynamic>>> entries(String planId) async =>
      (await open()).list('planEntries').then(
        (items) => items.where((item) => item['planId'] == planId).toList(),
      );

  Future<Map<String, dynamic>> generateEntry(
    String planId,
    String scheduledDate, {
    bool supplement = false,
  }) async {
    final storage = await open();
    return storage.transaction((session) async {
    final plan = await session.get('plans', planId);
    if (plan == null) throw const FormatException('定投计划不存在');
    if (!supplement && plan['enabled'] != true) throw const FormatException('定投计划已暂停');
    if (!_validPlanDate(plan, scheduledDate)) {
      throw const FormatException('执行日期与计划不匹配');
    }
    final dedupe = '$planId:$scheduledDate';
    final existing = (await session.list('planEntries')).where(
      (item) => item['planId'] == planId && item['scheduledDate'] == scheduledDate,
    );
    if (existing.isNotEmpty) return existing.first;
    final entry = <String, dynamic>{
      'id': 'local-entry-${DateTime.now().microsecondsSinceEpoch}',
      'dedupeKey': dedupe,
      'planId': planId,
      'fundCode': plan['fundCode'],
      'fundName': plan['fundName'],
      'mode': plan['mode'],
      'amount': plan['amount'],
      'shares': plan['shares'],
      'scheduledDate': scheduledDate,
      'status': 'pending',
      'transactionId': null,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    await session.put('planEntries', entry['id'] as String, entry);
    return entry;
    });
  }

  Future<Map<String, dynamic>> skipEntry(String id) async {
    final storage = await open();
    return storage.transaction((session) async {
    final entry = await session.get('planEntries', id);
    if (entry == null) throw const FormatException('定投记录不存在');
    if (entry['status'] == 'skipped') return entry;
    if (entry['status'] != 'pending') {
      throw const FormatException('该定投记录不可跳过');
    }
    final next = {
      ...entry,
      'status': 'skipped',
      'skippedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await session.put('planEntries', id, next);
    return next;
    });
  }

  Future<Map<String, dynamic>> updateEntry(String id, String date, String note) async {
    final storage = await open();
    return storage.transaction((session) async {
      final entry = await session.get('planEntries', id);
      if (entry == null || entry['status'] != 'pending') {
        throw const FormatException('仅待记账记录可修改');
      }
      final plan = await session.get('plans', '${entry['planId']}');
      if (plan == null || !_validPlanDate(plan, date) || note.trim().length > 200) {
        throw const FormatException('执行日期或备注无效');
      }
      final duplicate = (await session.list('planEntries')).any((other) =>
          other['id'] != id && other['planId'] == entry['planId'] &&
          other['scheduledDate'] == date);
      if (duplicate) throw const FormatException('该执行日期已有定投记录');
      final next = {...entry, 'scheduledDate': date,
        'dedupeKey': '${entry['planId']}:$date', 'note': note.trim()};
      await session.put('planEntries', id, next);
      return next;
    });
  }

  /// Confirm the user's debit, creating exactly one pending NAV transaction.
  Future<Map<String, dynamic>> confirmEntry(String id) async {
    final storage = await open();
    return storage.transaction((session) async {
      final entry = await session.get('planEntries', id);
      if (entry == null) throw const FormatException('定投记录不存在');
      if (['confirmed', 'pending-confirmation'].contains(entry['status'])) return entry;
      if (entry['status'] != 'pending') throw const FormatException('该定投记录不可确认');
      final plan = await session.get('plans', '${entry['planId']}');
      if (plan == null) throw const FormatException('定投计划不存在');
      final mode = entry['mode'];
      final value = num.tryParse('${entry[mode]}');
      if (!['amount', 'shares'].contains(mode) || value == null || !value.isFinite || value <= 0) {
        throw const FormatException('定投金额或份额无效');
      }
      final transactionId = 'local-plan-entry:$id';
      final now = DateTime.now().toUtc().toIso8601String();
      const reason = '缺少对应交易日正式净值，等待净值确认';
      final fundCode = '${entry['fundCode']}';
      final fund = await session.get('funds', fundCode);
      if (fund == null) {
        await session.put('funds', fundCode, {
          'code': fundCode, 'name': entry['fundName'], 'type': plan['fundType'] ?? '',
        });
      }
      await session.put('transactions', transactionId, {
        'id': transactionId, 'clientRequestId': 'plan-entry:$id',
        'fundCode': fundCode, 'fundName': entry['fundName'],
        'fundType': fund?['type'] ?? plan['fundType'] ?? '',
        'type': 'buy', 'entryMode': mode,
        'amount': mode == 'amount' ? value : 0, 'shares': mode == 'shares' ? value : 0,
        'feeMode': 'rate', 'feeRate': 0, 'fixedFee': 0,
        'date': entry['scheduledDate'], 'cutoff': 'before',
        'note': entry['note'] ?? '', 'source': '定投确认',
        'status': 'pending', 'pendingReason': reason, 'createdAt': now,
      });
      final next = {...entry, 'status': 'pending-confirmation',
        'transactionId': transactionId, 'pendingReason': reason, 'confirmedAt': now};
      await session.put('planEntries', id, next);
      return next;
    });
  }

  bool _validPlanDate(Map<String, dynamic> plan, String date) {
    final parsed = DateTime.tryParse(date);
    if (!_validDate(date) || parsed == null || date.compareTo('${plan['startDate']}') < 0) {
      return false;
    }
    final day = parsed.weekday;
    return plan['cycle'] == 'weekly'
        ? day == plan['executionDay']
        : parsed.day == plan['executionDay'];
  }
}

class LocalQuotaRepository {
  LocalQuotaRepository(this.open);
  final Future<Repository> Function() open;

  Future<List<Map<String, dynamic>>> list() async =>
      (await open()).list('quotaOverrides');

  Future<Map<String, dynamic>> save({
    required String code,
    required String name,
    required String category,
    required String status,
    required String limit,
  }) async {
    if (!RegExp(r'^\d{6}$').hasMatch(code) || name.trim().isEmpty) {
      throw const FormatException('额度基金信息无效');
    }
    if (status.trim().isEmpty || limit.trim().isEmpty) {
      throw const FormatException('额度字段不能为空');
    }
    final record = <String, dynamic>{
      'code': code,
      'name': name.trim(),
      'category': category.trim(),
      'status': status.trim(),
      'limit': limit.trim(),
      'valueSource': 'user',
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await (await open()).put('quotaOverrides', code, record);
    return record;
  }

  Future<void> restore(String code) async =>
      (await open()).delete('quotaOverrides', code);
}

Future<String> exportLocalJson(Repository storage) async {
  final data = <String, List<Map<String, dynamic>>>{};
  for (final collection in importCollections) {
    data[collection] = await storage.list(collection);
  }
  return const JsonEncoder.withIndent('  ').convert({
    'format': importFormat,
    'version': importVersion,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'data': data,
  });
}

/// Never promote a transaction without a verified trade-date NAV and settlement.
/// The local NAV settlement pipeline is still pending implementation.
Future<List<Map<String, dynamic>>> confirmLocalPending(Repository storage, LocalNavRepository nav) async {
  return storage.transaction((session) async {
    final records = await session.list('transactions');
    final confirmed = <Map<String, dynamic>>[];
    for (final record in records) {
      if (record['status'] != 'pending') continue;
      final start = '${record['date']}';
      final snapshot = await nav.forDate('${record['fundCode']}', start, cutoff: '${record['cutoff']}', session: session);
      if (snapshot == null) {
        final next = {...record, 'pendingReason': '缺少对应交易日正式净值，等待净值确认'};
        await session.put('transactions', '${record['id']}', next);
        continue;
      }
      final price = num.tryParse('${snapshot['nav']}')!.toDouble();
      final input = num.tryParse('${record[record['entryMode']]}')!.toDouble();
      final feeRate = num.tryParse('${record['feeRate'] ?? 0}')?.toDouble() ?? 0;
      final fixedFee = num.tryParse('${record['fixedFee'] ?? 0}')?.toDouble() ?? 0;
      final fee = record['feeMode'] == 'fixed' ? fixedFee : (record['type'] == 'buy' && record['entryMode'] == 'amount' ? input - input / (1 + feeRate / 100) : input * feeRate / 100);
      final shares = record['entryMode'] == 'amount' ? (input - fee) / price : input;
      final amount = record['entryMode'] == 'amount' ? input : input * price + (record['type'] == 'buy' ? fee : 0);
      final next = {...record, 'status': 'confirmed', 'amount': (amount * 100).round() / 100, 'shares': (shares * 100).round() / 100, 'fee': (fee * 100).round() / 100, 'tradeNav': price, 'navDate': snapshot['navDate'], 'pendingReason': null};
      await session.put('transactions', '${record['id']}', next);
      final fund = await session.get('funds', '${record['fundCode']}');
      if (fund != null) {
        await session.put('funds', '${record['fundCode']}', {...fund, 'nav': price, 'navDate': snapshot['navDate'], 'navSource': snapshot['source'] ?? 'local-nav-cache'});
      }
      confirmed.add(next);
    }
    return confirmed;
  });
}
