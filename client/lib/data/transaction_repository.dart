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
      !['amount', 'shares'].contains(entryMode) ||
      cutoff is! String ||
      !['before', 'after'].contains(cutoff) ||
      date is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) {
    throw const FormatException('交易字段无效');
  }
  final rawValue = num.tryParse('${draft[entryMode]}');
  if (rawValue == null || !rawValue.isFinite || rawValue <= 0) {
    throw const FormatException('金额或份额必须大于0');
  }
  final value = (rawValue * 100).round() / 100;
  if (value <= 0) throw const FormatException('金额或份额最小精度为0.01');

  final feeMode = draft['feeMode'] == null
      ? (draft['fixedFee'] != null ? 'fixed' : 'rate')
      : '${draft['feeMode']}';
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
  LocalTransactionRepository(this.open, {LocalNavRepository? nav}) : nav = nav ?? LocalNavRepository(open);
  final Future<Repository> Function() open;
  final LocalNavRepository nav;

  @override
  Future<List<Map<String, dynamic>>> list() async =>
      (await open()).list('transactions');

  @override
  Future<Map<String, dynamic>> preview(Map<String, dynamic> draft) async => {
    ...normalizeTransaction(draft),
    'status': 'pending',
    'pendingReason': '本地模式暂未连接正式净值，交易保存为待确认',
  };

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
      'pendingReason': '本地模式暂未连接正式净值，交易保存为待确认',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    await storage.put('transactions', record['id'] as String, record);
    final settled = await confirmPending();
    return settled.firstWhere((item) => item['id'] == record['id'], orElse: () => record);
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
    final path = method == 'GET' || method == 'create'
        ? '/api/transactions'
        : method == 'confirm'
        ? '/api/transactions/confirm'
        : method == 'preview'
        ? '/api/transactions/preview'
        : '/api/transactions/${method.substring('cancel:'.length)}';
    final uri = apiUri(path);
    final response = method == 'GET'
        ? await client.get(uri, headers: headers)
        : method.startsWith('cancel:')
        ? await client.delete(uri, headers: headers)
        : await client.post(
            uri,
            headers: headers,
            body: draft == null ? null : jsonEncode(draft),
          );
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
  Future<void> close() async => client.close();
}
