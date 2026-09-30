import 'dart:convert';
import 'package:http/http.dart' as http;
import 'fund_catalog_repository.dart';
import 'fund_repository.dart';
import 'repository.dart';

typedef Quota = Map<String, dynamic>;

String? quotaCategory(String name) {
  if (RegExp(r'纳斯达克\s*100|纳指\s*100|NASDAQ\s*100', caseSensitive: false).hasMatch(name)) return '纳斯达克100';
  if (RegExp(r'标普\s*500|S&P\s*500|SP500', caseSensitive: false).hasMatch(name)) return '标普500';
  return null;
}

bool quotaCandidate(Quota fund) => quotaCategory('${fund['name']}') != null &&
    LocalFundCatalogRepository.supported(fund);

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

abstract interface class QuotaRepository {
  Future<List<Quota>> list();
  Future<List<Quota>> refresh();
  Future<void> setOverride(String code, Quota fields);
  Future<void> restore(String code);
}

class EastmoneyQuotaSource {
  EastmoneyQuotaSource({http.Client? client}) : client = client ?? http.Client();
  final http.Client client;
  static Quota parse(String html, Quota fund) {
    final clean = html.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll('&nbsp;', ' ').replaceAll('&amp;', '&').replaceAll(RegExp(r'\s+'), ' ');
    final status = RegExp(r'交易状态[：:]\s*(?:</?[^>]+>\s*)*([^<]+)').firstMatch(html);
    final limit = RegExp(r'单日累计购买上限\s*([\d,.]+)\s*(万|亿)?元').firstMatch(clean);
    final rate = RegExp(r'近一年(?:收益率|收益)?[：:\s]*([+-]?[\d.]+)\s*%').firstMatch(clean);
    final detail = RegExp(r'(?:申购说明|详情说明|基金概况)[：:\s]*([^。；]{2,120})').firstMatch(clean);
    return {
      'code': fund['code'], 'name': fund['name'], 'category': quotaCategory('${fund['name']}'),
      'status': quotaStatus(status?.group(1) ?? ''),
      'limit': limit == null ? null : quotaAmount(limit.group(1))! * (limit.group(2) == '万' ? 10000 : limit.group(2) == '亿' ? 100000000 : 1),
      'annualReturn': rate == null ? null : double.tryParse(rate.group(1)!)! / 100,
      'detail': detail?.group(1), 'source': '东方财富基金详情页',
      'sourceType': 'public', 'adapterId': 'eastmoney-quota-v2',
      'sourceUrl': 'https://fund.eastmoney.com/${fund['code']}.html',
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
  }
  Future<Quota> fetch(Quota fund) async {
    final response = await client.get(Uri.parse('https://fund.eastmoney.com/${fund['code']}.html'),
      headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw Exception('额度数据源暂时不可用');
    final html = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (!html.contains('交易状态')) throw Exception('额度页面格式已变化');
    return parse(html, fund);
  }
  void close() => client.close();
}

class LocalAutomaticQuotaRepository implements QuotaRepository {
  LocalAutomaticQuotaRepository(this.open, {EastmoneyQuotaSource? source, LocalFundCatalogRepository? catalog})
      : source = source ?? EastmoneyQuotaSource(), catalog = catalog ?? LocalFundCatalogRepository(open);
  final Future<Repository> Function() open;
  final EastmoneyQuotaSource source;
  final LocalFundCatalogRepository catalog;
  Future<List<Quota>>? _refreshing;
  @override
  Future<List<Quota>> list() async {
    final storage = await open();
    final bases = {for (final q in await storage.list('quotas')) '${q['code']}': q};
    final overrides = {for (final q in await storage.list('quotaOverrides')) '${q['code']}': q};
    return { ...bases, ...overrides }.keys.map((code) {
      final base = bases[code];
      final user = overrides[code];
      final fields = user?['overrideFields'] as List? ?? (user == null ? [] : ['status', 'limit']);
      final q = <String, dynamic>{...?base, ...?user};
      for (final field in ['status', 'limit']) {
        q[field] = fields.contains(field) ? (user == null ? null : user[field]) : (base == null ? null : base[field]);
        q[field == 'status' ? 'automaticStatus' : 'automaticLimit'] = base == null ? null : base[field];
      }
      q['status'] = quotaStatus('${q['status'] ?? ''}');
      q['limit'] = quotaAmount(q['limit']);
      q['valueSource'] = user == null ? 'automatic' : 'user';
      q['priority'] = q['valueSource'];
      q['overrideFields'] = fields;
      return q;
    }).toList();
  }
  @override
  Future<List<Quota>> refresh() => _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  Future<List<Quota>> _refresh() async {
    final storage = await open();
    await catalog.refreshIfStale();
    final funds = (await storage.list(fundCatalogCollection)).where(quotaCandidate).toList();
    if (funds.isEmpty) throw Exception('基金目录暂时不可用，请重试');
    var succeeded = 0;
    var failed = 0;
    // Bound requests to avoid flooding the source; preserve every failed fund.
    for (var i = 0; i < funds.length; i += 4) {
      await Future.wait(funds.skip(i).take(4).map((fund) async {
        try {
          final fresh = await source.fetch(fund);
          final code = '${fund['code']}';
          final old = await storage.get('quotas', code);
          if (old != null) {
            if (fresh['status'] == '未知') fresh['status'] = old['status'];
            if (fresh['limit'] == null) fresh['limit'] = old['limit'];
          }
          await storage.put('quotas', code, fresh);
          succeeded++;
        } catch (_) { failed++; }
      }));
    }
    if (succeeded == 0) throw Exception('额度数据源暂时不可用，已保留缓存');
    if (failed > 0) throw Exception('已更新 $succeeded 只，$failed 只刷新失败，已保留缓存');
    return list();
  }
  @override
  Future<void> setOverride(String code, Quota fields) async {
    if (!RegExp(r'^\d{6}$').hasMatch(code) || fields.isEmpty) throw const FormatException('额度字段无效');
    final storage = await open();
    final base = await storage.get('quotas', code);
    final old = await storage.get('quotaOverrides', code);
    if (base == null && old == null) throw const FormatException('额度记录不存在');
    final keys = {...?old?['overrideFields'] as List?, if (old != null && old['overrideFields'] == null) ...['status', 'limit'], ...fields.keys};
    final checked = <String, dynamic>{};
    if (fields.containsKey('status')) {
      if (!['开放申购', '暂停申购', '限大额', '未知'].contains(fields['status'])) throw const FormatException('申购状态无效');
      checked['status'] = fields['status'];
    }
    if (fields.containsKey('limit')) checked['limit'] = quotaAmount(fields['limit']);
    await storage.put('quotaOverrides', code, {...?base, ...?old, ...checked,
      'code': code, 'overrideFields': keys.toList(), 'valueSource': 'user',
      'updatedAt': DateTime.now().toUtc().toIso8601String()});
  }
  @override
  Future<void> restore(String code) async {
    final storage = await open();
    if (await storage.get('quotas', code) == null) {
      final old = await storage.get('quotaOverrides', code);
      if (old == null) throw const FormatException('额度记录不存在');
      final fresh = await source.fetch(old);
      await storage.put('quotas', code, fresh);
    }
    await storage.delete('quotaOverrides', code);
  }
  void close() { source.close(); catalog.close(); }
}

class RemoteQuotaRepository implements QuotaRepository {
  RemoteQuotaRepository({required this.token, http.Client? client}) : client = client ?? http.Client();
  final String token;
  final http.Client client;
  Future<dynamic> _request(String path, {String method = 'GET', Quota? fields}) async {
    final headers = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
    final uri = apiUri('/api/quotas$path');
    final response = await (method == 'PUT' ? client.put(uri, headers: headers, body: jsonEncode(fields))
      : method == 'POST' ? client.post(uri, headers: headers) : client.get(uri, headers: headers)).timeout(const Duration(seconds: 90));
    if (response.statusCode == 401) throw Exception('登录已失效，请重新登录');
    final body = jsonDecode(response.body);
    if (response.statusCode != 200) throw Exception(body is Map ? body['error'] ?? '额度请求失败' : '额度请求失败');
    return body;
  }
  @override
  Future<List<Quota>> list() async => (await _request('') as List).cast<Quota>();
  @override
  Future<List<Quota>> refresh() async => ((await _request('/refresh', method: 'POST'))['items'] as List).cast<Quota>();
  @override
  Future<void> setOverride(String code, Quota fields) async { await _request('/$code', method: 'PUT', fields: fields); }
  @override
  Future<void> restore(String code) async { await _request('/$code/restore', method: 'POST'); }
  void close() => client.close();
}
