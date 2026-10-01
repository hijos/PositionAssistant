import 'dart:convert';

import 'package:http/http.dart' as http;

import 'repository.dart';

class LocalNavRepository {
  LocalNavRepository(this.open, {http.Client? client})
    : client = client ?? http.Client();
  final Future<Repository> Function() open;
  final http.Client client;

  Future<Map<String, dynamic>?> forDate(
    String code,
    String date, {
    String? cutoff,
    RepositorySession? session,
  }) async {
    date = DateTime.parse(date)
        .add(Duration(days: cutoff == 'after' ? 1 : 0))
        .toIso8601String()
        .substring(0, 10);
    final storage = session ?? await open();
    final cached =
        (await storage.list('navSnapshots'))
            .where(
              (x) =>
                  x['fundCode'] == code &&
                  '${x['navDate']}'.compareTo(date) >= 0,
            )
            .toList()
          ..sort((a, b) => '${a['navDate']}'.compareTo('${b['navDate']}'));
    if (cached.isNotEmpty) return cached.first;
    try {
      final rows = <dynamic>[];
      // Eastmoney may ignore the date range and caps page size at 20, so walk
      // pages until the requested date is covered instead of trusting page 1.
      for (var page = 1; page <= 10; page++) {
        final response = await client
            .get(
              Uri.https('api.fund.eastmoney.com', '/f10/lsjz', {
                'fundCode': code,
                'pageIndex': '$page',
                'pageSize': '20',
              }),
              headers: {'Referer': 'https://fund.eastmoney.com/'},
            )
            .timeout(const Duration(seconds: 10));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          return null;
        }
        final body = jsonDecode(response.body);
        final pageRows = body is Map && body['Data'] is Map
            ? body['Data']['LSJZList']
            : null;
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
        if (navDate.compareTo(date) >= 0 &&
            nav != null &&
            nav.isFinite &&
            nav > 0 &&
            (selected == null ||
                navDate.compareTo('${selected['navDate']}') < 0)) {
          selected = {
            'id': '$code:$navDate:remote',
            'fundCode': code,
            'navDate': navDate,
            'nav': nav,
            'source': 'eastmoney-local-nav-v1',
          };
        }
      }
      if (selected != null) {
        await storage.put('navSnapshots', selected['id'] as String, selected);
      }
      return selected;
    } catch (_) {
      return null;
    }
  }

  /// Refreshes the latest official NAV for every locally saved fund.
  ///
  /// The holdings view derives formal market value and profit from the
  /// fund-level `nav`/`navDate` fields, which otherwise only advance when a
  /// transaction is confirmed. Pulling the newest snapshot here keeps the
  /// portfolio view current. Failures leave the previous values untouched.
  Future<void> refreshLatest() async {
    final storage = await open();
    final funds = await storage.list('funds');
    for (final fund in funds) {
      final code = fund['code'];
      if (code is! String || !RegExp(r'^\d{6}$').hasMatch(code)) continue;
      final fetched = await _fetchLatest(code);
      if (fetched != null) {
        await storage.put(
        'navSnapshots',
        fetched['id'] as String,
        fetched,
      );
      }
      final current = await storage.get('funds', code);
      if (current == null) continue;
      // A QDII NAV can lag a US close even when today's NAV request fails.
      // Estimate from the newest known valuation date, not publication time.
      final snapshot = fetched != null &&
              '${fetched['navDate']}'.compareTo('${current['navDate'] ?? ''}') >= 0
          ? fetched
          : current;
      if (num.tryParse('${snapshot['nav']}') == null ||
          snapshot['navDate'] is! String) {
        continue;
      }
      await storage.put('funds', code, {
        ...current,
        'nav': snapshot['nav'],
        'navDate': snapshot['navDate'],
        if (snapshot['dailyChange'] != null)
          'dailyChange': snapshot['dailyChange'],
        'navSource': snapshot['source'] ?? 'local-nav-cache',
        ...await _estimateFromProxy(
          snapshot['nav'] as num,
          snapshot['navDate'] as String,
          current,
        ),
      });
    }
  }

  Future<Map<String, dynamic>> _estimateFromProxy(
    num nav,
    String navDate,
    Map<String, dynamic> fund,
  ) async {
    final symbol = _proxySymbol(fund);
    if (symbol == null) return const {};
    try {
      final qqq = await _fetchYahooQuote(symbol, navDate);
      final fx = await _fetchYahooQuote('CNY=X', navDate);
      final dates = qqq.keys
          .where((date) => date.compareTo(navDate) > 0 && fx.containsKey(date))
          .toList()
        ..sort();
      if (dates.isEmpty) throw StateError('暂无晚于正式净值日的共同行情');
      final date = dates.last;
      final rate = (qqq[date]! / qqq[navDate]!) *
              (fx[date]! / fx[navDate]!) -
          1;
      final estimatedNav = (nav * (1 + rate) * 1000000).round() / 1000000;
      return {
        'estimatedNav': estimatedNav,
        'estimateAt': '${date}T23:59:59.000Z',
        'estimateSource': '$symbol + USD/CNY（Yahoo Finance，100%代理）',
        'estimateCoverage': 1.0,
        'estimateRuleVersion': 'qqq-fx-v1',
        'estimateBaseDate': navDate,
        'estimateMarketDate': date,
        'estimateError': null,
        'estimateMethod': '按 QQQ + USD/CNY 组合涨跌估算（100%）；不含费用、分红与调仓',
      };
    } catch (error) {
      return {
        'estimatedNav': null,
        'estimateRuleVersion': 'qqq-fx-v1',
        'estimateSource': '$symbol + USD/CNY（Yahoo Finance，100%代理）',
        'estimateError': '$error',
      };
    }
  }

  String? _proxySymbol(Map<String, dynamic> fund) {
    final text = '${fund['name'] ?? ''} ${fund['type'] ?? ''}'.toUpperCase();
    if (text.contains('标普') ||
        text.contains('S&P') ||
        text.contains('SP500') ||
        text.contains('标普500')) {
      return 'VOO';
    }
    if (text.contains('纳斯达克') ||
        text.contains('NASDAQ') ||
        text.contains('NAS100') ||
        text.contains('NDX')) {
      return 'QQQ';
    }
    return null;
  }

  Future<Map<String, double>> _fetchYahooQuote(
    String symbol,
    String baseDate,
  ) async {
    final start = DateTime.parse(baseDate)
        .subtract(const Duration(days: 7))
        .millisecondsSinceEpoch ~/ 1000;
    final end = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 86400;
    final response = await client
        .get(Uri.parse(
          'https://query1.finance.yahoo.com/v8/finance/chart/$symbol'
          '?interval=1d&period1=$start&period2=$end',
        ), headers: {'User-Agent': 'Mozilla/5.0'})
        .timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('行情请求失败');
    }
    final result = (jsonDecode(response.body) as Map)['chart']?['result']?[0];
    if (result is! Map) throw StateError('行情响应无效');
    final timestamps = result['timestamp'];
    final closes = result['indicators']?['quote']?[0]?['close'];
    if (timestamps is! List || closes is! List) {
      throw StateError('行情数据缺失');
    }
    final points = <String, double>{};
    // Yahoo FX daily bars start at London midnight, which can be the
    // previous UTC date. Use the exchange offset when assigning dates.
    final offset = num.tryParse('${result['meta']?['gmtoffset'] ?? 0}') ?? 0;
    for (var i = 0; i < timestamps.length && i < closes.length; i++) {
      final timestamp = num.tryParse('${timestamps[i]}');
      final close = num.tryParse('${closes[i]}');
      if (timestamp == null || close == null || close <= 0) continue;
      final date = DateTime.fromMillisecondsSinceEpoch(
        (timestamp.toInt() + offset.toInt()) * 1000,
        isUtc: true,
      ).toIso8601String().substring(0, 10);
      points[date] = close.toDouble();
    }
    if (!points.containsKey(baseDate)) throw StateError('缺少基准日行情');
    return points;
  }

  Future<Map<String, dynamic>?> _fetchLatest(String code) async {
    try {
      final response = await client
          .get(
            Uri.https('api.fund.eastmoney.com', '/f10/lsjz', {
              'fundCode': code,
              'pageIndex': '1',
              'pageSize': '1',
            }),
            headers: {'Referer': 'https://fund.eastmoney.com/'},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final body = jsonDecode(response.body);
      final rows = body is Map && body['Data'] is Map
          ? body['Data']['LSJZList']
          : null;
      if (rows is! List || rows.isEmpty || rows.first is! Map) return null;
      final raw = rows.first as Map;
      final navDate = '${raw['FSRQ'] ?? ''}';
      final nav = num.tryParse('${raw['DWJZ']}');
      final dailyChange = num.tryParse('${raw['JZZZL']}');
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(navDate) ||
          nav == null ||
          !nav.isFinite ||
          nav <= 0) {
        return null;
      }
      return {
        'id': '$code:$navDate:remote',
        'fundCode': code,
        'navDate': navDate,
        'nav': nav,
        if (dailyChange != null && dailyChange.isFinite)
          'dailyChange': dailyChange.toDouble(),
        'source': 'eastmoney-local-nav-v1',
      };
    } catch (_) {
      return null;
    }
  }
}
