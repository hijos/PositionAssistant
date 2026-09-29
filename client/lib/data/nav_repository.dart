import 'dart:convert';

import 'package:http/http.dart' as http;


import 'repository.dart';

class LocalNavRepository {
  LocalNavRepository(this.open, {http.Client? client}) : client = client ?? http.Client();
  final Future<Repository> Function() open;
  final http.Client client;

  Future<Map<String, dynamic>?> forDate(String code, String date, {String? cutoff, RepositorySession? session}) async {
    date = DateTime.parse(date).add(Duration(days: cutoff == 'after' ? 1 : 0)).toIso8601String().substring(0, 10);
    final storage = session ?? await open();
    final cached = (await storage.list('navSnapshots')).where((x) => x['fundCode'] == code && '${x['navDate']}'.compareTo(date) >= 0).toList()
      ..sort((a, b) => '${a['navDate']}'.compareTo('${b['navDate']}'));
    if (cached.isNotEmpty) return cached.first;
    try {
      final rows = <dynamic>[];
      // Eastmoney may ignore the date range and caps page size at 20, so walk
      // pages until the requested date is covered instead of trusting page 1.
      for (var page = 1; page <= 10; page++) {
        final response = await client.get(Uri.https('api.fund.eastmoney.com', '/f10/lsjz', {'fundCode': code, 'pageIndex': '$page', 'pageSize': '20'}), headers: {'Referer': 'https://fund.eastmoney.com/'}).timeout(const Duration(seconds: 10));
        if (response.statusCode < 200 || response.statusCode >= 300) return null;
        final body = jsonDecode(response.body);
        final pageRows = body is Map && body['Data'] is Map ? body['Data']['LSJZList'] : null;
        if (pageRows is! List || pageRows.isEmpty) break;
        rows.addAll(pageRows);
        final oldest = '${pageRows.last is Map ? pageRows.last['FSRQ'] : ''}';
        if (oldest.isNotEmpty && oldest.compareTo(date) <= 0) break;
      }
      Map<String, dynamic>? selected;
      for (final raw in rows) {
        if (raw is! Map) continue;
        final navDate = '${raw['FSRQ'] ?? ''}';
        final nav = num.tryParse('${raw['DWJZ']}');
        if (navDate.compareTo(date) >= 0 && nav != null && nav.isFinite && nav > 0 && (selected == null || navDate.compareTo('${selected['navDate']}') < 0)) {
          selected = {'id': '$code:$navDate:remote', 'fundCode': code, 'navDate': navDate, 'nav': nav, 'source': 'eastmoney-local-nav-v1'};
        }
      }
      if (selected != null) await storage.put('navSnapshots', selected['id'] as String, selected);
      return selected;
    } catch (_) { return null; }
  }
}


