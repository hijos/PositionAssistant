import 'dart:convert';

import 'package:http/http.dart' as http;

import 'fund_repository.dart';
import 'repository.dart';

abstract interface class HoldingRepository {
  Future<List<Map<String, dynamic>>> list();
  Future<void> close();
}

double _number(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

double? _optionalNumber(dynamic value) {
  if (value == null) return null;
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  return parsed != null && parsed.isFinite ? parsed : null;
}

double _money(double value) =>
    (value.isFinite ? (value * 100).roundToDouble() / 100 : 0);

class LocalHoldingRepository implements HoldingRepository {
  LocalHoldingRepository(this.open);
  final Future<Repository> Function() open;

  @override
  Future<List<Map<String, dynamic>>> list() async {
    final storage = await open();
    final funds = await storage.list('funds');
    final fundByCode = {
      for (final fund in funds)
        if (fund['code'] is String) fund['code'] as String: fund,
    };
    final confirmed =
        (await storage.list('transactions'))
            .where((record) => record['status'] == 'confirmed')
            .toList()
          ..sort((a, b) {
            final date = '${a['date'] ?? ''}'.compareTo('${b['date'] ?? ''}');
            if (date != 0) return date;
            return (a['cutoff'] == 'after' ? 1 : 0).compareTo(
              b['cutoff'] == 'after' ? 1 : 0,
            );
          });

    final grouped = <String, Map<String, dynamic>>{};
    for (final transaction in confirmed) {
      final code = transaction['fundCode'];
      if (code is! String || code.isEmpty) continue;
      final holding = grouped[code] ??= {
        'fundCode': code,
        'fundName':
            transaction['fundName'] ?? fundByCode[code]?['name'] ?? code,
        'shares': 0.0,
        'invested': 0.0,
        'redeemed': 0.0,
        'cost': 0.0,
        'realizedProfit': 0.0,
        'transactions': 0,
      };
      final shares = _number(transaction['shares']);
      if (transaction['type'] == 'buy') {
        final amount = _number(transaction['amount']);
        holding['shares'] = _number(holding['shares']) + shares;
        holding['invested'] = _number(holding['invested']) + amount;
        holding['cost'] = _number(holding['cost']) + amount;
      } else if (transaction['type'] == 'sell') {
        final available = _number(holding['shares']);
        if (shares > available + 0.000001) {
          throw const FormatException('卖出份额超过历史持仓');
        }
        final cost = available == 0
            ? 0
            : _number(holding['cost']) * shares / available;
        final proceeds =
            _number(transaction['amount']) - _number(transaction['fee']);
        holding['shares'] = available - shares;
        holding['redeemed'] = _number(holding['redeemed']) + proceeds;
        holding['cost'] = _number(holding['cost']) - cost;
        holding['realizedProfit'] =
            _number(holding['realizedProfit']) + proceeds - cost;
      }
      holding['transactions'] = (holding['transactions'] as int) + 1;
    }

    return grouped.values.map((holding) {
      final fund = fundByCode[holding['fundCode']];
      final nav = _optionalNumber(fund?['nav']);
      final navDate = fund?['navDate'];
      final valid =
          nav != null && nav > 0 && navDate is String && navDate.isNotEmpty;
      final shares = _number(holding['shares']);
      final cost = _money(_number(holding['cost']));
      final marketValue = valid ? _money(shares * nav) : null;
      final profit = marketValue == null ? null : _money(marketValue - cost);
      final estimatedNav = _optionalNumber(fund?['estimatedNav']);
      final estimateValid = estimatedNav != null && estimatedNav > 0 && valid;
      final estimatedMarketValue = estimateValid
          ? _money(shares * estimatedNav)
          : null;
      final estimatedProfit = estimatedMarketValue == null
          ? null
          : _money(estimatedMarketValue - cost);
      return {
        ...holding,
        'shares': _money(shares),
        'invested': _money(_number(holding['invested'])),
        'redeemed': _money(_number(holding['redeemed'])),
        'cost': cost,
        'realizedProfit': _money(_number(holding['realizedProfit'])),
        'nav': valid ? nav : null,
        'navDate': valid ? navDate : null,
        'marketValue': marketValue,
        'profit': profit,
        'profitRate': profit == null || cost == 0 ? null : profit / cost,
        'estimatedNav': estimateValid ? estimatedNav : null,
        'estimatedMarketValue': estimatedMarketValue,
        'estimatedProfit': estimatedProfit,
        'estimateAt': fund?['estimateAt'],
        'estimateSource': fund?['estimateSource'],
        'estimateCoverage': fund?['estimateCoverage'],
        'holdingsDate': fund?['holdingsDate'],
        'estimateRuleVersion': fund?['estimateRuleVersion'],
        'estimateError': fund?['estimateError'],
      };
    }).toList();
  }

  @override
  Future<void> close() async {}
}

class RemoteHoldingRepository implements HoldingRepository {
  RemoteHoldingRepository({required this.token, http.Client? client})
    : client = client ?? http.Client();
  final String token;
  final http.Client client;

  @override
  Future<List<Map<String, dynamic>>> list() async {
    if (token.isEmpty) throw Exception('请先登录');
    final response = await client
        .get(
          apiUri('/api/holdings'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode == 401) throw Exception('登录已失效，请重新登录');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String? error;
      try {
        final value = (jsonDecode(response.body) as Map)['error'];
        if (value is String) error = value;
      } catch (_) {}
      throw Exception(error ?? '持仓读取失败，请重试');
    }
    final value = jsonDecode(response.body);
    if (value is! List) throw Exception('持仓响应无效');
    return value.cast<Map<String, dynamic>>();
  }

  @override
  Future<void> close() async => client.close();
}
