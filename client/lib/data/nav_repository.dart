import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'repository.dart';

class LocalNavRepository {
  LocalNavRepository(
    this.open, {
    http.Client? client,
    this.cacheTtl = const Duration(minutes: 10),
    DateTime Function()? clock,
    Random? random,
  }) : client = client ?? http.Client(),
       _clock = clock ?? DateTime.now,
       _random = random ?? Random();

  static const _navFetchMetaCollection = 'navFetchMeta';
  static const _marketQuoteCacheCollection = 'marketQuoteCache';
  final Future<Repository> Function() open;
  final http.Client client;
  final Duration cacheTtl;
  final DateTime Function() _clock;
  final Random _random;
  final Map<String, Future<Map<String, dynamic>?>> _navFetches = {};
  final Map<String, Future<Map<String, double>>> _marketFetches = {};
  Future<void>? _refreshLatestFuture;

  Future<Map<String, dynamic>?> latestQqqDailyChange() async {
    try {
      final points = await _fetchMarketQuoteWindow('QQQ');
      final dates = points.keys.toList()..sort();
      if (dates.length < 2) return null;
      final latestDate = dates.last;
      final previousDate = dates[dates.length - 2];
      final latest = points[latestDate]!;
      final previous = points[previousDate]!;
      return {
        'dailyChange': (latest / previous - 1) * 100,
        'navDate': latestDate,
      };
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> latest(
    String code, {
    RepositorySession? session,
  }) async {
    final storage = session ?? await open();
    return _fetchLatestCached(code, storage);
  }

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
            .where((x) => x['fundCode'] == code && '${x['navDate']}' == date)
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
    final pending = _refreshLatestFuture;
    if (pending != null) return pending;
    final future = _refreshLatestInternal();
    _refreshLatestFuture = future;
    try {
      await future;
    } finally {
      if (identical(_refreshLatestFuture, future)) {
        _refreshLatestFuture = null;
      }
    }
  }

  Future<void> _refreshLatestInternal() async {
    final storage = await open();
    final funds = (await storage.list('funds'))
        .where(
          (fund) =>
              fund['code'] is String &&
              RegExp(r'^\d{6}$').hasMatch(fund['code'] as String),
        )
        .toList();
    if (funds.isEmpty) return;

    final quoteCache = <String, Future<Map<String, double>>>{};
    final fetchedByCode = <String, Map<String, dynamic>>{};
    final attemptedCodes = <String>{};
    final refreshMeta = await storage.get(_navFetchMetaCollection, 'latest');

    // A random fund is a cheap probe for a new official NAV date.  When it has
    // not changed, the remaining fund NAV endpoints are left untouched; their
    // cached NAVs are still enough to recompute proxy estimates.
    if (!_isFresh(refreshMeta?['attemptedAt'])) {
      final probeCode = funds[_random.nextInt(funds.length)]['code'] as String;
      attemptedCodes.add(probeCode);
      final probe = await _fetchLatestCached(probeCode, storage, force: true);
      if (probe != null) fetchedByCode[probeCode] = probe;
      final current = await storage.get('funds', probeCode);
      final probeDate = '${probe?['navDate'] ?? ''}';
      final currentDate = '${current?['navDate'] ?? ''}';
      final dateChanged =
          probe != null &&
          (currentDate.isEmpty || probeDate.compareTo(currentDate) > 0);
      if (dateChanged) {
        for (final fund in funds) {
          final code = fund['code'] as String;
          if (code == probeCode) continue;
          attemptedCodes.add(code);
          final fetched = await _fetchLatestCached(code, storage, force: true);
          if (fetched != null) fetchedByCode[code] = fetched;
        }
      }
      await storage.put(_navFetchMetaCollection, 'latest', {
        'id': 'latest',
        'attemptedAt': _nowMilliseconds,
        'probeCode': probeCode,
        if (probe != null) 'probeNavDate': probe['navDate'],
      });
    }

    // A newly added fund has no usable local NAV yet.  Fetch it even when the
    // ten-minute batch gate is still fresh, otherwise it could remain empty
    // until the next global refresh window.
    for (final fund in funds) {
      final code = fund['code'] as String;
      final current = await storage.get('funds', code);
      if (attemptedCodes.contains(code) || _hasUsableNav(current)) continue;
      attemptedCodes.add(code);
      final fetched = await _fetchLatestCached(code, storage);
      if (fetched != null) fetchedByCode[code] = fetched;
    }

    for (final fund in funds) {
      final code = fund['code'] as String;
      final fetched = fetchedByCode[code];
      final current = await storage.get('funds', code);
      if (current == null) continue;
      // A QDII NAV can lag a US close even when today's NAV request fails.
      // Estimate from the newest known valuation date, not publication time.
      final snapshot =
          fetched != null &&
              '${fetched['navDate']}'.compareTo(
                    '${current['navDate'] ?? ''}',
                  ) >=
                  0
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
          quoteCache,
        ),
      });
    }
  }

  Future<Map<String, dynamic>?> _fetchLatestCached(
    String code,
    RepositorySession storage, {
    bool force = false,
  }) async {
    final pending = _navFetches[code];
    if (pending != null) return pending;
    final future = _fetchLatestCachedInternal(code, storage, force: force);
    _navFetches[code] = future;
    try {
      return await future;
    } finally {
      if (identical(_navFetches[code], future)) _navFetches.remove(code);
    }
  }

  Future<Map<String, dynamic>?> _fetchLatestCachedInternal(
    String code,
    RepositorySession storage, {
    required bool force,
  }) async {
    final cached = await _cachedLatest(storage, code);
    final meta = await storage.get(_navFetchMetaCollection, code);
    if (!force && _isFresh(meta?['attemptedAt'])) return cached;

    await storage.put(_navFetchMetaCollection, code, {
      'id': code,
      'attemptedAt': _nowMilliseconds,
    });
    final fetched = await _fetchLatest(code);
    if (fetched != null) {
      await storage.put('navSnapshots', fetched['id'] as String, fetched);
      await storage.put(_navFetchMetaCollection, code, {
        'id': code,
        'attemptedAt': _nowMilliseconds,
        'lastSuccessAt': _nowMilliseconds,
      });
      return fetched;
    }
    // Keep the failed attempt timestamp so repeated tab switches do not turn
    // an upstream outage into a request storm.  A cached snapshot remains
    // usable by the holdings and transaction flows.
    return cached;
  }

  Future<Map<String, dynamic>?> _cachedLatest(
    RepositorySession storage,
    String code,
  ) async {
    final cached =
        (await storage.list('navSnapshots'))
            .where((x) => x['fundCode'] == code)
            .toList()
          ..sort((a, b) => '${b['navDate']}'.compareTo('${a['navDate']}'));
    return cached.isEmpty ? null : cached.first;
  }

  bool _hasUsableNav(Map<String, dynamic>? fund) {
    final nav = num.tryParse('${fund?['nav']}');
    return nav != null &&
        nav.isFinite &&
        nav > 0 &&
        RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch('${fund?['navDate']}');
  }

  int get _nowMilliseconds => _clock().millisecondsSinceEpoch;

  bool _isFresh(dynamic timestamp) {
    final value = int.tryParse('$timestamp');
    if (value == null) return false;
    final age = _nowMilliseconds - value;
    return age >= 0 && age < cacheTtl.inMilliseconds;
  }

  Future<Map<String, dynamic>> _estimateFromProxy(
    num nav,
    String navDate,
    Map<String, dynamic> fund,
    Map<String, Future<Map<String, double>>> quoteCache,
  ) async {
    final symbol = _proxySymbol(fund);
    if (symbol == null) return const {};
    try {
      final qqq = await (quoteCache['$symbol:$navDate'] ??= _fetchMarketQuote(
        symbol,
        navDate,
      ));
      final fx = await (quoteCache['CNY=X:$navDate'] ??= _fetchMarketQuote(
        'CNY=X',
        navDate,
      ));
      final dates =
          qqq.keys
              .where(
                (date) => date.compareTo(navDate) > 0 && fx.containsKey(date),
              )
              .toList()
            ..sort();
      if (dates.isEmpty) throw StateError('暂无晚于正式净值日的共同行情');
      final date = dates.last;
      final rate =
          (qqq[date]! / qqq[navDate]!) * (fx[date]! / fx[navDate]!) - 1;
      final estimatedNav = (nav * (1 + rate) * 1000000).round() / 1000000;
      return {
        'estimatedNav': estimatedNav,
        'estimateAt': '${date}T23:59:59.000Z',
        'estimateSource': '$symbol + USD/CNY（东方财富，100%代理）',
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
        'estimateSource': '$symbol + USD/CNY（东方财富/Yahoo备用，100%代理）',
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
    String? baseDate,
  ) async {
    final start =
        (baseDate == null ? DateTime.now() : DateTime.parse(baseDate))
            .subtract(const Duration(days: 7))
            .millisecondsSinceEpoch ~/
        1000;
    final end = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 86400;
    http.Response? response;
    for (final host in [
      'query1.finance.yahoo.com',
      'query2.finance.yahoo.com',
    ]) {
      try {
        final candidate = await client
            .get(
              Uri.parse(
                'https://$host/v8/finance/chart/$symbol'
                '?interval=1d&period1=$start&period2=$end',
              ),
              headers: {
                'User-Agent': 'Mozilla/5.0',
                'Accept': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 10));
        if (candidate.statusCode >= 200 && candidate.statusCode < 300) {
          response = candidate;
          break;
        }
      } catch (_) {
        // Try the second Yahoo host before reporting the estimate unavailable.
      }
    }
    if (response == null) throw StateError('QQQ/汇率行情接口不可用');
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
    if (baseDate != null && !points.containsKey(baseDate)) {
      throw StateError('缺少基准日行情');
    }
    return points;
  }

  Future<Map<String, double>> _fetchMarketQuote(
    String symbol,
    String baseDate,
  ) async {
    final storage = await open();
    final cached = await storage.get(_marketQuoteCacheCollection, symbol);
    final cachedPoints = _marketPoints(cached?['points']);
    if (_isFresh(cached?['attemptedAt']) &&
        cachedPoints.containsKey(baseDate)) {
      return cachedPoints;
    }
    final pending = _marketFetches[symbol];
    if (pending != null) {
      final points = await pending;
      if (points.containsKey(baseDate)) return points;
    }
    final future = _fetchAndCacheMarketQuote(
      symbol,
      baseDate: baseDate,
      storage: storage,
      cachedPoints: cachedPoints,
    );
    _marketFetches[symbol] = future;
    try {
      final points = await future;
      if (!points.containsKey(baseDate)) throw StateError('缺少基准日行情');
      return points;
    } finally {
      if (identical(_marketFetches[symbol], future)) {
        _marketFetches.remove(symbol);
      }
    }
  }

  Future<Map<String, double>> _fetchMarketQuoteWindow(String symbol) async {
    final storage = await open();
    final cached = await storage.get(_marketQuoteCacheCollection, symbol);
    final cachedPoints = _marketPoints(cached?['points']);
    if (_isFresh(cached?['attemptedAt']) && cachedPoints.length >= 2) {
      return cachedPoints;
    }
    final pending = _marketFetches[symbol];
    if (pending != null) {
      final points = await pending;
      if (points.length >= 2) return points;
    }
    final future = _fetchAndCacheMarketQuote(
      symbol,
      storage: storage,
      cachedPoints: cachedPoints,
    );
    _marketFetches[symbol] = future;
    try {
      final points = await future;
      if (points.length < 2) throw StateError('行情数据不足');
      return points;
    } finally {
      if (identical(_marketFetches[symbol], future)) {
        _marketFetches.remove(symbol);
      }
    }
  }

  Future<Map<String, double>> _fetchAndCacheMarketQuote(
    String symbol, {
    String? baseDate,
    required Repository storage,
    required Map<String, double> cachedPoints,
  }) async {
    final attemptedAt = _nowMilliseconds;
    await storage.put(_marketQuoteCacheCollection, symbol, {
      'id': symbol,
      'attemptedAt': attemptedAt,
      'points': cachedPoints,
    });
    try {
      final fetched = await _fetchMarketQuoteFromNetwork(symbol, baseDate);
      final merged = {...cachedPoints, ...fetched};
      await storage.put(_marketQuoteCacheCollection, symbol, {
        'id': symbol,
        'attemptedAt': _nowMilliseconds,
        'lastSuccessAt': _nowMilliseconds,
        'points': merged,
      });
      return merged;
    } catch (error) {
      // Preserve a usable stale quote and throttle retries for the same
      // ten-minute window when the upstream source is rate-limited.
      await storage.put(_marketQuoteCacheCollection, symbol, {
        'id': symbol,
        'attemptedAt': _nowMilliseconds,
        'points': cachedPoints,
      });
      if (baseDate == null
          ? cachedPoints.length >= 2
          : cachedPoints.containsKey(baseDate)) {
        return cachedPoints;
      }
      rethrow;
    }
  }

  Future<Map<String, double>> _fetchMarketQuoteFromNetwork(
    String symbol,
    String? baseDate,
  ) async {
    try {
      return await _fetchEastmoneyQuote(symbol, baseDate);
    } catch (_) {
      return _fetchYahooQuote(symbol == 'CNY=X' ? 'CNY=X' : symbol, baseDate);
    }
  }

  Map<String, double> _marketPoints(dynamic raw) {
    if (raw is! Map) return <String, double>{};
    final points = <String, double>{};
    for (final entry in raw.entries) {
      final value = num.tryParse('${entry.value}');
      if (value != null && value.isFinite && value > 0) {
        points['${entry.key}'] = value.toDouble();
      }
    }
    return points;
  }

  Future<Map<String, double>> _fetchEastmoneyQuote(
    String symbol,
    String? baseDate,
  ) async {
    final secid = switch (symbol) {
      'QQQ' => '105.QQQ',
      'VOO' => '107.VOO',
      'CNY=X' => '133.USDCNH',
      _ => throw StateError('不支持的东方财富标的'),
    };
    final start = (baseDate == null ? DateTime.now() : DateTime.parse(baseDate))
        .subtract(Duration(days: baseDate == null ? 14 : 7))
        .toIso8601String()
        .substring(0, 10)
        .replaceAll('-', '');
    final end = DateTime.now()
        .add(const Duration(days: 1))
        .toIso8601String()
        .substring(0, 10)
        .replaceAll('-', '');
    final response = await client
        .get(
          Uri.parse(
            'https://push2his.eastmoney.com/api/qt/stock/kline/get'
            '?secid=$secid&klt=101&fqt=1&beg=$start&end=$end'
            '&fields1=f1&fields2=f51,f52,f53,f54,f55,f56,f57,f58',
          ),
          headers: {'Referer': 'https://quote.eastmoney.com/'},
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('东方财富行情请求失败');
    }
    final data = (jsonDecode(response.body) as Map)['data'];
    final rows = data is Map ? data['klines'] : null;
    if (rows is! List || rows.isEmpty) throw StateError('东方财富行情为空');
    final points = <String, double>{};
    for (final row in rows) {
      if (row is! String) continue;
      final fields = row.split(',');
      if (fields.length < 3) continue;
      final close = double.tryParse(fields[2]);
      if (close != null && close > 0) points[fields[0]] = close;
    }
    if (baseDate != null && !points.containsKey(baseDate)) {
      throw StateError('东方财富缺少基准日行情');
    }
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
