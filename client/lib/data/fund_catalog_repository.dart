import 'dart:convert';

import 'package:http/http.dart' as http;

import 'repository.dart';

const fundCatalogCollection = 'fund_catalog';
const fundCatalogUrl = 'https://fund.eastmoney.com/js/fundcode_search.js';

class LocalFundCatalogRepository {
  LocalFundCatalogRepository(this.open, {http.Client? client})
    : client = client ?? http.Client();
  final Future<Repository> Function() open;
  final http.Client client;
  Future<void>? _refreshing;

  Future<List<Map<String, dynamic>>> search(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return [];
    final repository = await open();
    final local = await repository.list(fundCatalogCollection);
    final matches = _search(local, normalized);
    if (matches.isNotEmpty) return matches;
    try {
      await refresh(repository);
      return _search(await repository.list(fundCatalogCollection), normalized);
    } catch (_) {
      return matches;
    }
  }

  Future<bool> refreshIfStale({Duration maxAge = const Duration(days: 1)}) async {
    final Repository repository;
    try {
      repository = await open();
    } catch (_) {
      // Desktop preview and widget tests cannot open local storage; the
      // catalog is optional there, so report "not refreshed" instead of
      // throwing through the page lifecycle.
      return false;
    }
    final rows = await repository.list(fundCatalogCollection);
    final latest = rows
        .map((row) => DateTime.tryParse('${row['updatedAt'] ?? ''}'))
        .whereType<DateTime>()
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    if (latest != null && DateTime.now().toUtc().difference(latest).abs() < maxAge) {
      return false;
    }
    try {
      await refresh(repository);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<int> refresh([Repository? repository]) {
    final ongoing = _refreshing;
    if (ongoing != null) return ongoing.then((_) async => 0);
    final future = _refresh(repository);
    _refreshing = future.then((_) {}, onError: (_) {});
    return future.whenComplete(() => _refreshing = null);
  }

  Future<int> _refresh([Repository? repository]) async {
    final target = repository ?? await open();
    final response = await client
        .get(Uri.parse(fundCatalogUrl), headers: const {'User-Agent': 'Mozilla/5.0', 'Accept-Charset': 'utf-8'})
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw Exception('基金目录刷新失败');
    final rows = _parse(utf8.decode(response.bodyBytes, allowMalformed: true));
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    await target.transaction((session) async {
      for (final row in rows) {
        await session.put(fundCatalogCollection, row['code'] as String, {
          ...row,
          'updatedAt': updatedAt,
        });
      }
    });
    return rows.length;
  }

  void close() => client.close();

  static List<Map<String, dynamic>> _search(
    List<Map<String, dynamic>> rows,
    String query,
  ) => rows
      .where(supported)
      .where((item) => [item['code'], item['name'], item['shortName']]
          .any((value) => '$value'.toLowerCase().contains(query)))
      .toList()
    ..sort((a, b) => (a['code'] == query ? 0 : 1).compareTo(b['code'] == query ? 0 : 1));

  static bool supported(Map<String, dynamic> item) {
    final text = '${item['name']} ${item['type']}'.toUpperCase();
    if (RegExp(r'美元|美钞|美汇|港币|港元|欧元|英镑|日元|澳元|加元|新加坡元|瑞士法郎|外币|外汇|USD|HKD|EUR|GBP|JPY|AUD|CAD|SGD|CHF').hasMatch(text)) return false;
    if (RegExp(r'LOF|场内|交易型|封闭|REIT').hasMatch(text)) return false;
    if (text.contains('ETF') && !RegExp(r'ETF[ -]*(联接|连接)').hasMatch(item['name'].toString().toUpperCase())) return false;
    return RegExp(r'^(股票型|混合型|债券型|货币型|指数型|QDII|FOF)(-|$)').hasMatch(item['type'].toString().toUpperCase()) || item['type'].toString().toUpperCase().startsWith('指数型');
  }

  static List<Map<String, dynamic>> _parse(String body) {
    final text = body.replaceFirst('\ufeff', '').trim();
    final match = RegExp(r'^var\s+r\s*=\s*(\[[\s\S]*\])\s*;?$', multiLine: false).firstMatch(text);
    if (match == null) throw Exception('基金目录格式无效');
    final rows = jsonDecode(match.group(1)!) as List;
    return rows.map((row) {
      if (row is! List || row.length < 4 || !RegExp(r'^\d{6}$').hasMatch('${row[0]}')) throw Exception('基金目录记录无效');
      return {'code': '${row[0]}', 'shortName': '${row[1]}', 'name': '${row[2]}', 'type': '${row[3]}'};
    }).toList();
  }
}
