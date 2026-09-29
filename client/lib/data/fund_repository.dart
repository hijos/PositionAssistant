import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'repository.dart';

Uri apiUri(String path) {
  const configured = String.fromEnvironment('API_BASE_URL');
  return (configured.isNotEmpty
          ? Uri.parse(configured)
          : kIsWeb
          ? Uri.base
          : Uri.parse('http://127.0.0.1:3000'))
      .resolve(path);
}

abstract interface class FundRepository {
  Future<List<Map<String, dynamic>>> list();
  Future<Map<String, dynamic>> add(Map<String, dynamic> fund);
  Future<void> remove(String code);
}

Map<String, dynamic> fundRecord(Map<String, dynamic> fund) {
  if (fund['code'] is! String ||
      !RegExp(r'^\d{6}$').hasMatch(fund['code']) ||
      fund['name'] is! String ||
      (fund['name'] as String).trim().isEmpty ||
      fund['type'] is! String) {
    throw const FormatException('基金信息无效');
  }
  return {'code': fund['code'], 'name': fund['name'], 'type': fund['type']};
}

class LocalFundRepository implements FundRepository {
  LocalFundRepository(this.open);
  final Future<Repository> Function() open;
  @override
  Future<List<Map<String, dynamic>>> list() async =>
      (await open()).list('funds');
  @override
  Future<Map<String, dynamic>> add(Map<String, dynamic> fund) async {
    final record = fundRecord(fund);
    return (await open()).transaction((session) async {
      final old = await session.get('funds', record['code']);
      if (old != null) return old;
      await session.put('funds', record['code'], record);
      return record;
    });
  }
  @override
  Future<void> remove(String code) async {
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw const FormatException('基金代码无效');
    }
    await (await open()).transaction((session) async {
      await session.delete('funds', code);
    });
  }
}

class RemoteFundRepository implements FundRepository {
  RemoteFundRepository({required this.token, http.Client? client})
    : client = client ?? http.Client();
  final String token;
  final http.Client client;
  Future<dynamic> request([Map<String, dynamic>? fund]) async {
    if (token.isEmpty) throw Exception('请先登录');
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    final uri = apiUri('/api/my-funds');
    final response =
        await (fund == null
                ? client.get(uri, headers: headers)
                : client.post(
                    uri,
                    headers: headers,
                    body: jsonEncode({'code': fundRecord(fund)['code']}),
                  ))
            .timeout(const Duration(seconds: 20));
    if (response.statusCode == 401) throw Exception('登录已失效，请重新登录');
    if (response.statusCode != 200) throw Exception('基金保存或读取失败，请重试');
    return jsonDecode(response.body);
  }

  @override
  Future<List<Map<String, dynamic>>> list() async =>
      (await request() as List).cast<Map<String, dynamic>>();
  @override
  Future<Map<String, dynamic>> add(Map<String, dynamic> fund) async =>
      (await request(fund)) as Map<String, dynamic>;
  @override
  Future<void> remove(String code) async {
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw const FormatException('基金代码无效');
    }
    if (token.isEmpty) throw Exception('请先登录');
    final response = await client
        .delete(
          apiUri('/api/my-funds/$code'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode == 401) throw Exception('登录已失效，请重新登录');
    if (response.statusCode != 204 && response.statusCode != 404) {
      throw Exception('基金删除失败，请重试');
    }
  }
  Future<void> logout() async {
    await client
        .post(
          apiUri('/api/auth/logout'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 20));
  }

  void close() => client.close();
}
