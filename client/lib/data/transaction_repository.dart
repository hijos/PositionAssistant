import 'dart:convert';

import 'package:http/http.dart' as http;

import 'fund_repository.dart';
import 'repository.dart';
import 'offline_repository.dart';
import 'nav_repository.dart';

abstract interface class TransactionRepository {
  Future<List<Map<String, dynamic>>> list();
  Future<Map<String, dynamic>> preview(Map<String, dynamic> draft);
  Future<Map<String, dynamic>> create(Map<String, dynamic> draft);
  Future<List<Map<String, dynamic>>> confirmPending();
  Future<Map<String, dynamic>> cancel(String id);

  /// Permanently removes a cancelled record; other statuses stay untouched.
  Future<void> deleteCancelled(String id);

  /// Permanently removes every cancelled record and returns the delete count.
  Future<int> clearCancelled();

  Future<void> close();
}

Map<String, dynamic> normalizeTransaction(Map<String, dynamic> draft) {
  final code = draft['fundCode'];
  final name = draft['fundName'];
  final type = draft['fundType'];
  final entryMode = draft['entryMode'];
  final cutoff = draft['cutoff'];
  final date = draft['date'];
  final transactionType = draft['type'] ?? 'buy';
  if (transactionType is! String ||
      !['buy', 'sell'].contains(transactionType) ||
      code is! String ||
      !RegExp(r'^\d{6}$').hasMatch(code) ||
      name is! String ||
      name.trim().isEmpty ||
      type is! String ||
      entryMode is! String ||
      !['amount', 'shares', 'holding'].contains(entryMode) ||
      cutoff is! String ||
      !['before', 'after'].contains(cutoff) ||
      date is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) {
    throw const FormatException('交易字段无效');
  }
  if (entryMode == 'holding' && transactionType != 'buy') {
    throw const FormatException('持有金额录入仅支持买入');
  }
  final rawValue = num.tryParse(
    '${entryMode == 'holding' ? draft['holdingAmount'] : draft[entryMode]}',
  );
  if (rawValue == null || !rawValue.isFinite || rawValue <= 0) {
    throw const FormatException('金额或份额必须大于0');
  }
  final value = (rawValue * 100).round() / 100;
  if (value <= 0) throw const FormatException('金额或份额最小精度为0.01');

  final holdingProfit = entryMode == 'holding'
      ? num.tryParse('${draft['holdingProfit']}')
      : 0;
  if (entryMode == 'holding' &&
      (holdingProfit == null ||
          !holdingProfit.isFinite ||
          holdingProfit >= value)) {
    throw const FormatException('持有收益必须是有效金额且小于持有金额');
  }
  final feeMode = entryMode == 'holding'
      ? 'fixed'
      : (draft['feeMode'] == null
            ? (draft['fixedFee'] != null ? 'fixed' : 'rate')
            : '${draft['feeMode']}');
  if (!['rate', 'fixed'].contains(feeMode)) {
    throw const FormatException('手续费模式无效');
  }
  num parseFee(dynamic raw) {
    if (raw == null || (raw is String && raw.trim().isEmpty)) return 0;
    final parsed = num.tryParse('$raw');
    if (parsed == null) throw const FormatException('手续费参数无效');
    return parsed;
  }

  final feeRate = parseFee(draft['feeRate']);
  final fixedFee = parseFee(draft['fixedFee']);
  if (!feeRate.isFinite ||
      feeRate < 0 ||
      feeRate >= 100 ||
      !fixedFee.isFinite ||
      fixedFee < 0 ||
      (feeMode == 'rate' && fixedFee != 0) ||
      (feeMode == 'fixed' && feeRate != 0)) {
    throw const FormatException('手续费参数无效');
  }
  return {
    'fundCode': code,
    'fundName': name.trim(),
    'fundType': type,
    'type': transactionType,
    'entryMode': entryMode,
    'amount': entryMode == 'amount' ? value : 0,
    'shares': entryMode == 'shares' ? value : 0,
    'holdingAmount': entryMode == 'holding' ? value : null,
    'holdingProfit': entryMode == 'holding' ? holdingProfit : null,
    'feeMode': feeMode,
    'feeRate': feeMode == 'rate' ? feeRate : 0,
    'fixedFee': feeMode == 'fixed' ? (fixedFee * 100).round() / 100 : 0,
    'date': date,
    'cutoff': cutoff,
    'note': optionalText(draft['note'], 200),
    'source': optionalText(draft['source'], 100),
    if (draft['clientRequestId'] != null)
      'clientRequestId': optionalText(draft['clientRequestId'], 128),
  };
}

/// Backwards-compatible buy-only validation for callers that explicitly need it.
Map<String, dynamic> normalizeBuy(Map<String, dynamic> draft) {
  if (draft['type'] != null && draft['type'] != 'buy') {
    throw const FormatException('买入交易字段无效');
  }
  return normalizeTransaction({...draft, 'type': 'buy'});
}

void validateHistoricalSell(
  Map<String, dynamic> draft,
  List<Map<String, dynamic>> transactions,
) {
  if (draft['type'] != 'sell' || draft['entryMode'] != 'shares') return;
  final code = draft['fundCode'];
  final requested = num.tryParse('${draft['shares']}');
  if (code is! String || requested == null || !requested.isFinite) return;
  final records =
      [
        ...transactions.where(
          (record) =>
              record['fundCode'] == code && record['status'] == 'confirmed',
        ),
        {...draft, 'status': 'confirmed'},
      ]..sort((a, b) {
        final date = '${a['date']}'.compareTo('${b['date']}');
        if (date != 0) return date;
        return (a['cutoff'] == 'after' ? 1 : 0).compareTo(
          b['cutoff'] == 'after' ? 1 : 0,
        );
      });
  var available = 0.0;
  for (final record in records) {
    final shares = num.tryParse('${record['shares']}')?.toDouble() ?? 0;
    if (record['type'] == 'buy') {
      available += shares;
    } else {
      if (shares > available + 0.000001) {
        throw const FormatException('卖出份额超过历史持仓');
      }
      available -= shares;
    }
  }
}

void validateConfirmedLedger(Iterable<Map<String, dynamic>> transactions) {
  final byFund = <String, List<Map<String, dynamic>>>{};
  for (final record in transactions) {
    if (record['status'] != 'confirmed') continue;
    final code = record['fundCode'];
    if (code is String) byFund.putIfAbsent(code, () => []).add(record);
  }
  for (final records in byFund.values) {
    records.sort((a, b) {
      final date = '${a['date']}'.compareTo('${b['date']}');
      if (date != 0) return date;
      return (a['cutoff'] == 'after' ? 1 : 0).compareTo(
        b['cutoff'] == 'after' ? 1 : 0,
      );
    });
    var available = 0.0;
    for (final record in records) {
      final shares = num.tryParse('${record['shares']}')?.toDouble() ?? 0;
      if (record['type'] == 'buy') {
        available += shares;
      } else if (shares > available + 0.000001) {
        throw const FormatException('卖出份额超过历史持仓');
      } else {
        available -= shares;
      }
    }
  }
}

String optionalText(dynamic value, int maxLength) {
  if (value == null) return '';
  if (value is! String) throw const FormatException('备注或来源无效');
  final text = value.trim();
  if (text.length > maxLength) throw const FormatException('备注或来源过长');
  return text;
}

class LocalTransactionRepository implements TransactionRepository {
  LocalTransactionRepository(this.open, {LocalNavRepository? nav})
    : nav = nav ?? LocalNavRepository(open);
  final Future<Repository> Function() open;
  final LocalNavRepository nav;

  @override
  Future<List<Map<String, dynamic>>> list() async =>
      (await open()).list('transactions');

  @override
  Future<Map<String, dynamic>> preview(Map<String, dynamic> draft) async {
    final normalized = normalizeTransaction(draft);
    final snapshot = normalized['entryMode'] == 'holding'
        ? await nav.latest('${normalized['fundCode']}')
        : await nav.forDate(
            '${normalized['fundCode']}',
            '${normalized['date']}',
            cutoff: '${normalized['cutoff']}',
          );
    if (snapshot == null) {
      return {
        ...normalized,
        'status': 'pending',
        'pendingReason': '对应交易日正式净值尚未公布或暂时无法获取',
      };
    }
    return _settlePreview(normalized, snapshot);
  }

  Map<String, dynamic> _settlePreview(
    Map<String, dynamic> record,
    Map<String, dynamic> snapshot,
  ) {
    final price = num.tryParse('${snapshot['nav']}')!.toDouble();
    if (record['entryMode'] == 'holding') {
      final marketValue = num.tryParse('${record['holdingAmount']}')!
          .toDouble();
      final profit = holdingProfitForRecord(record);
      final cost = marketValue - profit;
      return {
        ...record,
        'status': 'preview',
        'nav': price,
        'tradeNav': price,
        'navDate': snapshot['navDate'],
        'amount': (cost * 100).round() / 100,
        'shares': (marketValue / price * 100).round() / 100,
        'fee': 0,
        'pendingReason': null,
      };
    }
    final input = num.tryParse('${record[record['entryMode']]}')!.toDouble();
    final feeRate = num.tryParse('${record['feeRate'] ?? 0}')?.toDouble() ?? 0;
    final fixedFee =
        num.tryParse('${record['fixedFee'] ?? 0}')?.toDouble() ?? 0;
    final fee = record['feeMode'] == 'fixed'
        ? fixedFee
        : (record['type'] == 'buy' && record['entryMode'] == 'amount'
              ? input - input / (1 + feeRate / 100)
              : input * feeRate / 100);
    final shares = record['entryMode'] == 'amount'
        ? (input - fee) / price
        : input;
    final amount = record['entryMode'] == 'amount'
        ? input
        : input * price + (record['type'] == 'buy' ? fee : 0);
    return {
      ...record,
      'status': 'preview',
      'nav': price,
      'tradeNav': price,
      'navDate': snapshot['navDate'],
      'amount': (amount * 100).round() / 100,
      'shares': (shares * 100).round() / 100,
      'fee': (fee * 100).round() / 100,
      'pendingReason': null,
    };
  }

  @override
  Future<Map<String, dynamic>> create(Map<String, dynamic> draft) async {
    final normalized = normalizeTransaction(draft);
    final storage = await open();
    final requestId = draft['clientRequestId'];
    if (requestId is String && requestId.isNotEmpty) {
      for (final record in await storage.list('transactions')) {
        if (record['clientRequestId'] == requestId) return record;
      }
    }
    validateHistoricalSell(normalized, await storage.list('transactions'));
    final record = {
      ...normalized,
      'id': 'local-${DateTime.now().microsecondsSinceEpoch}',
      'status': 'pending',
      'pendingReason': '对应交易日正式净值尚未公布或暂时无法获取',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    await storage.put('transactions', record['id'] as String, record);
    final settled = await confirmPending();
    return settled.firstWhere(
      (item) => item['id'] == record['id'],
      orElse: () => record,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> confirmPending() async =>
      confirmLocalPending(await open(), nav);

  @override
  Future<Map<String, dynamic>> cancel(String id) async {
    if (id.trim().isEmpty) throw const FormatException('交易记录编号无效');
    final storage = await open();
    return storage.transaction((session) async {
      final target = await session.get('transactions', id);
      if (target == null) throw const FormatException('交易记录不存在');
      if (target['status'] == 'cancelled') return target;
      final records = await session.list('transactions');
      validateConfirmedLedger(records.where((record) => record['id'] != id));
      final cancelled = {
        ...target,
        'status': 'cancelled',
        'cancelledAt': DateTime.now().toUtc().toIso8601String(),
      };
      await session.put('transactions', id, cancelled);
      return cancelled;
    });
  }

  @override
  Future<void> deleteCancelled(String id) async {
    if (id.trim().isEmpty) throw const FormatException('交易记录编号无效');
    final storage = await open();
    await storage.transaction((session) async {
      final target = await session.get('transactions', id);
      if (target == null) throw const FormatException('交易记录不存在');
      if (target['status'] != 'cancelled') {
        throw const FormatException('只能删除已取消交易，请先撤销该交易');
      }
      await session.delete('transactions', id);
    });
  }

  @override
  Future<int> clearCancelled() async {
    final storage = await open();
    return storage.transaction((session) async {
      final cancelled = (await session.list('transactions'))
          .where((record) => record['status'] == 'cancelled')
          .toList();
      for (final record in cancelled) {
        await session.delete('transactions', '${record['id']}');
      }
      return cancelled.length;
    });
  }

  @override
  Future<void> close() async {}
}

class RemoteTransactionRepository implements TransactionRepository {
  RemoteTransactionRepository({required this.token, http.Client? client})
    : client = client ?? http.Client();
  final String token;
  final http.Client client;

  Future<dynamic> request(String method, [Map<String, dynamic>? draft]) async {
    if (token.isEmpty) throw Exception('请先登录');
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    final cancelId = method.startsWith('cancel:')
        ? method.substring('cancel:'.length)
        : null;
    final deleteId = method.startsWith('delete:')
        ? method.substring('delete:'.length)
        : null;
    final path = switch (method) {
      'GET' || 'create' => '/api/transactions',
      'confirm' => '/api/transactions/confirm',
      'preview' => '/api/transactions/preview',
      'clearCancelled' => '/api/transactions/cancelled',
      _ when cancelId != null => '/api/transactions/$cancelId',
      _ when deleteId != null => '/api/transactions/$deleteId/permanent',
      _ => '/api/transactions/$method',
    };
    final uri = apiUri(path);
    final response = switch (method) {
      'GET' => await client.get(uri, headers: headers),
      'clearCancelled' => await client.delete(uri, headers: headers),
      _ when cancelId != null || deleteId != null => await client.delete(
        uri,
        headers: headers,
      ),
      _ => await client.post(
        uri,
        headers: headers,
        body: draft == null ? null : jsonEncode(draft),
      ),
    };
    if (response.statusCode == 401) throw Exception('登录已失效，请重新登录');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String? error;
      try {
        final value = (jsonDecode(response.body) as Map)['error'];
        if (value is String) error = value;
      } catch (_) {}
      throw Exception(error ?? '交易请求失败，请重试');
    }
    return response.body.isEmpty ? null : jsonDecode(response.body);
  }

  Map<String, dynamic> body(Map<String, dynamic> draft) {
    final normalized = normalizeTransaction(draft);
    return {
      ...normalized,
      // The server validates these fields and ignores the display-only names.
      'amount': normalized['amount'],
      'shares': normalized['shares'],
    };
  }

  @override
  Future<List<Map<String, dynamic>>> list() async =>
      (await request('GET') as List).cast<Map<String, dynamic>>();

  @override
  Future<Map<String, dynamic>> preview(Map<String, dynamic> draft) async =>
      (await request('preview', body(draft)) as Map).cast<String, dynamic>();

  @override
  Future<Map<String, dynamic>> create(Map<String, dynamic> draft) async =>
      (await request('create', body(draft)) as Map).cast<String, dynamic>();

  @override
  Future<List<Map<String, dynamic>>> confirmPending() async {
    final value = (await request('confirm') as Map).cast<String, dynamic>();
    final transactions = value['transactions'];
    return transactions is List
        ? transactions.cast<Map<String, dynamic>>()
        : <Map<String, dynamic>>[];
  }

  @override
  Future<Map<String, dynamic>> cancel(String id) async =>
      (await request('cancel:$id') as Map).cast<String, dynamic>();

  @override
  Future<void> deleteCancelled(String id) async {
    if (id.trim().isEmpty) throw const FormatException('交易记录编号无效');
    await request('delete:$id');
  }

  @override
  Future<int> clearCancelled() async {
    final value = (await request('clearCancelled') as Map)
        .cast<String, dynamic>();
    final deleted = value['deleted'];
    return deleted is num ? deleted.toInt() : 0;
  }

  @override
  Future<void> close() async => client.close();
}

double holdingProfitForRecord(Map<String, dynamic> record) {
  if (record['holdingProfit'] != null)
    return num.parse('${record['holdingProfit']}').toDouble();
  final amount = num.parse('${record['holdingAmount']}').toDouble();
  final rate = num.parse('${record['holdingReturnRate']}').toDouble();
  return amount - amount / (1 + rate / 100);
}
