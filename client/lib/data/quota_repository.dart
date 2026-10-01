import 'dart:convert';
import 'package:http/http.dart' as http;
import 'fund_catalog_repository.dart';
import 'fund_repository.dart';
import 'repository.dart';

typedef Quota = Map<String, dynamic>;

typedef QuotaChannel = Map<String, dynamic>;

String? quotaCategory(String name) {
  if (RegExp(r'纳斯达克\s*100|纳指\s*100|NASDAQ\s*100', caseSensitive: false).hasMatch(name)) return '纳斯达克100';
  if (RegExp(r'标普\s*500|S&P\s*500|SP500', caseSensitive: false).hasMatch(name)) return '标普500';
  return null;
}

bool quotaCandidate(Quota fund) => quotaCategory('${fund['name']}') != null && LocalFundCatalogRepository.supported(fund);

String quotaStatus(String raw) {
  if (raw.contains('暂停') || raw.contains('不开放')) return '暂停申购';
  if (raw.contains('限')) return '限大额';
  if (raw.contains('开放') || raw.contains('正常')) return '开放申购';
  return '未知';
}

double? quotaAmount(dynamic raw) {
  if (raw == null || '$raw'.trim().isEmpty) return null;
  final value = double.tryParse('$raw'.replaceAll(',', '').trim());
  if (value == null || !value.isFinite || value < 0) throw const FormatException('限额必须是非负金额或留空');
  return value;
}

QuotaChannel normalizeQuotaChannel(QuotaChannel? raw, [Quota fallback = const {}]) {
  final value = <String, dynamic>{...?raw};
  return {
    'status': value['status'] ?? '未知',
    'limit': value['limit'] == null ? null : quotaAmount(value['limit']),
    'limitType': value['limitType'] ?? 'per-account-daily',
    'directPlatform': value['directPlatform'] ?? fallback['directPlatform'],
    'source': value['source'],
    'sourceType': value['sourceType'],
    'sourceUrl': value['sourceUrl'],
    'effectiveFrom': value['effectiveFrom'],
    'updatedAt': value['updatedAt'] ?? fallback['updatedAt'],
    'adapterId': value['adapterId'],
    'error': value['error'],
  };
}

Quota normalizeQuota(Quota raw) {
  final source = <String, dynamic>{...raw};
  final legacy = source['channels'] is Map ? null : <String, dynamic>{
    'status': source['status'],
    'limit': source['limit'],
    'source': source['source'],
    'sourceType': source['sourceType'],
    'sourceUrl': source['sourceUrl'],
    'updatedAt': source['updatedAt'],
    'adapterId': source['adapterId'],
  };
  final channels = <String, dynamic>{};
  final rawChannels = source['channels'];
  if (rawChannels is Map) {
    for (final entry in rawChannels.entries) {
      channels['${entry.key}'] = normalizeQuotaChannel(entry.value is Map ? Map<String, dynamic>.from(entry.value) : null, source);
    }
  } else if (legacy!.values.any((value) => value != null)) {
    channels['distribution'] = normalizeQuotaChannel(legacy, source);
  }
  if (channels.isEmpty) channels['distribution'] = normalizeQuotaChannel(null, source);
  final direct = channels['direct'] as QuotaChannel?;
  final distribution = channels['distribution'] as QuotaChannel?;
  final preferred = direct != null && ['开放申购', '限大额'].contains(direct['status'])
      ? 'direct'
      : distribution != null && ['开放申购', '限大额'].contains(distribution['status'])
          ? 'distribution'
          : direct != null && direct['status'] != '未知' ? 'direct' : distribution != null ? 'distribution' : 'unknown';
  final selected = (channels[preferred] as QuotaChannel?) ?? distribution ?? direct ?? <String, dynamic>{};
  return {
    ...source,
    'channels': channels,
    'preferredChannel': preferred,
    'dataQuality': source['dataQuality'] ?? (channels.values.any((item) => item['sourceType'] == 'fund-manager-page' || item['sourceType'] == 'fund-manager-announcement') ? 'verified' : 'public'),
    'status': selected['status'] ?? '未知',
    'limit': selected['limit'],
    'source': selected['source'],
    'sourceType': selected['sourceType'],
    'sourceUrl': selected['sourceUrl'],
    'updatedAt': selected['updatedAt'] ?? source['updatedAt'],
  };
}

abstract interface class QuotaSource {
  String get id;
  String get channel;
  bool canHandle(Quota fund);
  Future<Quota> fetch(Quota fund);
  void close();
}

class EastmoneyQuotaSource implements QuotaSource {
  EastmoneyQuotaSource({http.Client? client}) : client = client ?? http.Client();
  final http.Client client;
  @override String get id => 'eastmoney-distribution-v2';
  @override String get channel => 'distribution';
  @override bool canHandle(Quota fund) => fund['code'] != null;
  static Quota parse(String html, Quota fund) {
    final clean = html.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll('&nbsp;', ' ').replaceAll('&amp;', '&').replaceAll(RegExp(r'\s+'), ' ');
    final status = RegExp(r'交易状态[：:]\s*(?:</?[^>]+>\s*)*([^<]+)').firstMatch(html);
    final limit = RegExp(r'单日累计购买上限\s*([\d,.]+)\s*(万|亿)?\s*元').firstMatch(clean);
    final rate = RegExp(r'近一年(?:收益率|收益)?[：:\s]*([+-]?[\d.]+)\s*%').firstMatch(clean);
    final detail = RegExp(r'(?:申购说明|详情说明|基金概况)[：:\s]*([^。；]{2,120})').firstMatch(clean);
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    final channel = <String, dynamic>{
      'status': quotaStatus(status?.group(1) ?? ''),
      'limit': limit == null ? null : quotaAmount(limit.group(1))! * (limit.group(2) == '万' ? 10000 : limit.group(2) == '亿' ? 100000000 : 1),
      'source': '东方财富基金详情页', 'sourceType': 'public', 'adapterId': 'eastmoney-distribution-v2',
      'sourceUrl': 'https://fund.eastmoney.com/${fund['code']}.html', 'updatedAt': updatedAt,
    };
    return normalizeQuota({
      'code': fund['code'], 'name': fund['name'], 'category': quotaCategory('${fund['name']}'),
      'annualReturn': rate == null ? null : double.tryParse(rate.group(1)!)! / 100,
      'detail': detail?.group(1), 'channels': {'distribution': channel}, 'updatedAt': updatedAt,
    });
  }
  @override Future<Quota> fetch(Quota fund) async {
    final response = await client.get(Uri.parse('https://fund.eastmoney.com/${fund['code']}.html'), headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw Exception('额度数据源暂时不可用');
    final html = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (!html.contains('交易状态')) throw Exception('额度页面格式已变化');
    return parse(html, fund);
  }
  @override void close() => client.close();
}

class FundManagerDirectQuotaSource implements QuotaSource {
  FundManagerDirectQuotaSource({http.Client? client}) : client = client ?? http.Client();
  final http.Client client;
  @override String get id => 'fund-manager-direct-v1';
  @override String get channel => 'direct';
  @override bool canHandle(Quota fund) => '${fund['directUrl'] ?? ''}'.trim().isNotEmpty;
  static Quota parse(String html, Quota fund) {
    final clean = html.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll('&nbsp;', ' ').replaceAll('&amp;', '&').replaceAll(RegExp(r'\s+'), ' ').trim();
    final statusText = RegExp(r'(?:交易状态|申购状态|销售状态)[：:\s]*([^。；|]{2,30})').firstMatch(clean)?.group(1) ?? '';
    final limit = RegExp(r'(?:单日累计购买上限|单日申购上限|单日限额)[：:\s]*([\d,.]+)\s*(万|亿)?\s*元').firstMatch(clean);
    final amount = limit == null ? null : quotaAmount(limit.group(1))! * (limit.group(2) == '万' ? 10000 : limit.group(2) == '亿' ? 100000000 : 1);
    final status = quotaStatus(statusText);
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    return normalizeQuota({...fund, 'channels': {'direct': {
      'status': status, 'limit': amount, 'directPlatform': 'fund-company-web',
      'source': fund['directSource'] ?? '基金公司直销公开页面', 'sourceType': 'fund-manager-page',
      'sourceUrl': fund['directUrl'], 'updatedAt': updatedAt, 'adapterId': 'fund-manager-direct-v1',
    }}});
  }
  @override Future<Quota> fetch(Quota fund) async {
    final response = await client.get(Uri.parse('${fund['directUrl']}'), headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw Exception('直销页面暂时不可用');
    return parse(utf8.decode(response.bodyBytes, allowMalformed: true), fund);
  }
  @override void close() => client.close();
}

abstract interface class QuotaRepository {
  Future<List<Quota>> list();
  Future<List<Quota>> refresh();
  Future<void> setOverride(String code, Quota fields);
  Future<void> restore(String code);
}

class LocalAutomaticQuotaRepository implements QuotaRepository {
  LocalAutomaticQuotaRepository(this.open, {EastmoneyQuotaSource? source, FundManagerDirectQuotaSource? directSource, LocalFundCatalogRepository? catalog})
      : source = source ?? EastmoneyQuotaSource(), directSource = directSource ?? FundManagerDirectQuotaSource(), catalog = catalog ?? LocalFundCatalogRepository(open);
  final Future<Repository> Function() open;
  final EastmoneyQuotaSource source;
  final FundManagerDirectQuotaSource directSource;
  final LocalFundCatalogRepository catalog;
  Future<List<Quota>>? _refreshing;
  @override Future<List<Quota>> list() async {
    final storage = await open();
    final bases = {for (final q in await storage.list('quotas')) '${q['code']}': normalizeQuota(q)};
    final overrides = {for (final q in await storage.list('quotaOverrides')) '${q['code']}': q};
    return {...bases, ...overrides}.keys.map((code) {
      final base = bases[code]; final user = overrides[code];
      if (base == null) return normalizeQuota({...?(user ?? <String, dynamic>{}), 'valueSource': 'user', 'priority': 'user'});
      final fields = (user?['overrideFields'] as List?)?.map((value) => '').toList() ?? <String>[];
      final channels = <String, dynamic>{for (final entry in (base['channels'] as Map).entries) entry.key: normalizeQuotaChannel(entry.value is Map ? Map<String, dynamic>.from(entry.value as Map) : null)};
      for (final field in fields) {
        final parts = field.split('.');
        if (parts.length == 3 && parts[0] == 'channels') {
          final channel = parts[1]; channels[channel] = normalizeQuotaChannel({...?(channels[channel] is Map ? Map<String, dynamic>.from(channels[channel] as Map) : <String, dynamic>{}), parts[2]: user?[field] ?? user?[parts[2]]});
        } else if (field == 'status' || field == 'limit') {
          channels['distribution'] = normalizeQuotaChannel({...?(channels['distribution'] is Map ? Map<String, dynamic>.from(channels['distribution'] as Map) : <String, dynamic>{}), field: user?[field]});
        }
      }
      return {...normalizeQuota({...base, 'channels': channels}), 'valueSource': user == null ? 'automatic' : 'user', 'priority': user == null ? 'automatic' : 'user', 'userOverride': user != null, 'overrideFields': fields, if (user != null) 'automaticChannels': base['channels']};
    }).toList();
  }
  @override Future<List<Quota>> refresh() => _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  Future<List<Quota>> _refresh() async {
    final storage = await open(); await catalog.refreshIfStale();
    final funds = (await storage.list(fundCatalogCollection)).where(quotaCandidate).toList(); if (funds.isEmpty) throw Exception('基金目录暂时不可用，请重试');
    var succeeded = 0, failed = 0;
    for (var i = 0; i < funds.length; i += 4) {
      await Future.wait(funds.skip(i).take(4).map((fund) async {
        try {
          final results = <Quota>[];
          if (source.canHandle(fund)) results.add(await source.fetch(fund));
          if (directSource.canHandle(fund)) results.add(await directSource.fetch(fund));
          if (results.isEmpty) throw Exception('没有可用额度来源');
          var fresh = normalizeQuota({...results.first, 'channels': {for (final item in results) ...Map<String, dynamic>.from(item['channels'] as Map)}});
          final old = await storage.get('quotas', '${fund['code']}');
          if (old != null) { final previous = normalizeQuota(old); fresh = normalizeQuota({...fresh, 'channels': {...previous['channels'] as Map, ...fresh['channels'] as Map}}); }
          await storage.put('quotas', '${fund['code']}', fresh); succeeded++;
        } catch (_) { failed++; }
      }));
    }
    if (succeeded == 0) throw Exception('额度数据源暂时不可用，已保留缓存');
    if (failed > 0) throw Exception('已更新 $succeeded 只，$failed 只刷新失败，已保留缓存');
    return list();
  }
  @override Future<void> setOverride(String code, Quota fields) async {
    final storage = await open(); final base = await storage.get('quotas', code); final old = await storage.get('quotaOverrides', code);
    if (base == null && old == null) throw const FormatException('额度记录不存在');
    final channel = '${fields['channel'] ?? 'distribution'}'; final patch = Map<String, dynamic>.from(fields)..remove('channel');
    final keys = <String>{...((old?['overrideFields'] as List?)?.map((value) => '') ?? const <String>[]), ...patch.keys.map((key) => 'channels..')};
    for (final key in patch.keys) { if (key == 'status' && !['开放申购', '暂停申购', '限大额', '未知'].contains(patch[key])) throw const FormatException('申购状态无效'); if (key == 'limit') patch[key] = quotaAmount(patch[key]); }
    await storage.put('quotaOverrides', code, {...?(old ?? <String, dynamic>{}), 'code': code, 'name': base?['name'] ?? old?['name'], 'channels': base?['channels'], ...patch, 'overrideFields': keys.toList(), 'valueSource': 'user', 'updatedAt': DateTime.now().toUtc().toIso8601String()});
  }
  @override Future<void> restore(String code) async { final storage = await open(); await storage.delete('quotaOverrides', code); }
  void close() { source.close(); directSource.close(); catalog.close(); }
}

class RemoteQuotaRepository implements QuotaRepository {
  RemoteQuotaRepository({required this.token, http.Client? client}) : client = client ?? http.Client();
  final String token; final http.Client client;
  Future<dynamic> _request(String path, {String method = 'GET', Quota? fields}) async {
    final headers = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}; final uri = apiUri('/api/quotas$path');
    final response = await (method == 'PUT' ? client.put(uri, headers: headers, body: jsonEncode(fields)) : method == 'POST' ? client.post(uri, headers: headers) : client.get(uri, headers: headers)).timeout(const Duration(seconds: 90));
    if (response.statusCode == 401) throw Exception('登录已失效，请重新登录'); final body = jsonDecode(response.body);
    if (response.statusCode != 200) throw Exception(body is Map ? body['error'] ?? '额度请求失败' : '额度请求失败'); return body;
  }
  @override Future<List<Quota>> list() async => (await _request('') as List).cast<Quota>().map(normalizeQuota).toList();
  @override Future<List<Quota>> refresh() async => ((await _request('/refresh', method: 'POST'))['items'] as List).cast<Quota>().map(normalizeQuota).toList();
  @override Future<void> setOverride(String code, Quota fields) async { await _request('/$code', method: 'PUT', fields: fields); }
  @override Future<void> restore(String code) async { await _request('/$code/restore', method: 'POST'); }
  void close() => client.close();
}





