import 'package:flutter/material.dart';

import 'data/transaction_repository.dart';
import 'transaction_history.dart';

class HoldingSelectionPage extends StatelessWidget {
  const HoldingSelectionPage({
    required this.holdings,
    required this.repository,
    this.errorMessage,
    super.key,
  });

  final List<Map<String, dynamic>> holdings;
  final TransactionRepository repository;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('持仓详情')),
    body: errorMessage != null
        ? Center(child: Text(errorMessage!))
        : holdings.isEmpty
        ? const Center(child: Text('暂无持仓'))
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('选择基金查看持仓详情'),
              const SizedBox(height: 8),
              for (final holding in holdings)
                Card(
                  child: ListTile(
                    title: Text(
                      '${holding['fundName'] ?? holding['fundCode']}',
                    ),
                    subtitle: Text(
                      '${holding['fundCode'] ?? '—'} · ${_shares(holding['shares'])} 份',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => HoldingDetailPage(
                          holding: holding,
                          repository: repository,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
  );
}

class HoldingDetailPage extends StatefulWidget {
  const HoldingDetailPage({
    required this.holding,
    required this.repository,
    super.key,
  });

  final Map<String, dynamic> holding;
  final TransactionRepository repository;

  @override
  State<HoldingDetailPage> createState() => _HoldingDetailPageState();
}

class _HoldingDetailPageState extends State<HoldingDetailPage> {
  late Future<List<Map<String, dynamic>>> records = _loadRecords();

  Future<List<Map<String, dynamic>>> _loadRecords() async {
    final code = widget.holding['fundCode'];
    final all = await widget.repository.list();
    return sortTransactions(
      all.where((item) => code != null && item['fundCode'] == code),
    );
  }

  void reload() => setState(() => records = _loadRecords());

  @override
  Widget build(BuildContext context) {
    final holding = widget.holding;
    return Scaffold(
      appBar: AppBar(title: const Text('持仓详情')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _summary(context, holding),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('关联交易', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: records,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const LinearProgressIndicator();
                      }
                      if (snapshot.hasError) {
                        return TextButton(
                          onPressed: reload,
                          child: const Text('交易读取失败，点击重试'),
                        );
                      }
                      final items = snapshot.data ?? const [];
                      if (items.isEmpty) return const Text('暂无关联交易');
                      return Column(
                        children: [
                          for (final item in items)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                '${item['type'] == 'buy' ? '买入' : '卖出'} · ${item['date'] ?? '未记录'}',
                              ),
                              subtitle: Text(_transactionSummary(item)),
                              trailing: _status(item['status']),
                              onTap: () async {
                                final changed = await Navigator.of(context)
                                    .push<bool>(
                                      MaterialPageRoute(
                                        builder: (_) => TransactionDetailPage(
                                          transaction: item,
                                          repository: widget.repository,
                                        ),
                                      ),
                                    );
                                if (changed == true && mounted) reload();
                              },
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summary(BuildContext context, Map<String, dynamic> item) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${item['fundName'] ?? item['fundCode'] ?? '基金'}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text('${item['fundCode'] ?? '—'}'),
          const Divider(height: 24),
          _row('当前份额', '${_number(item['shares']).toStringAsFixed(2)} 份'),
          _row('累计投入', _money(item['invested'])),
          _row('累计赎回', _money(item['redeemed'])),
          _row('剩余持仓成本', _money(item['cost'])),
          _row('已实现收益', _money(item['realizedProfit'])),
          _row(
            '正式净值',
            item['nav'] == null
                ? '—'
                : '${_number(item['nav'])}（${item['navDate'] ?? '—'}）',
          ),
          _row('正式市值', _money(item['marketValue'])),
          _row('正式持有收益', _money(item['profit'])),
          _row('正式收益率', _rate(item['profitRate'])),
          _row('估算净值', _money(item['estimatedNav'])),
          _row('估算市值', _money(item['estimatedMarketValue'])),
          _row('估算收益（参考）', _money(item['estimatedProfit'])),
          if (item['estimateSource'] != null)
            _row('估算来源', '${item['estimateSource']}'),
          if (item['estimateAt'] != null)
            _row('估算更新时间', '${item['estimateAt']}'),
          if (item['estimateCoverage'] != null)
            _row('披露持仓覆盖', '${_number(item['estimateCoverage']) * 100.0}%'),
          if (item['holdingsDate'] != null)
            _row('披露持仓日期', '${item['holdingsDate']}'),
        ],
      ),
    ),
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Flexible(child: Text(value, textAlign: TextAlign.end)),
      ],
    ),
  );

  Widget _status(dynamic value) {
    final (label, color) = switch (value) {
      'confirmed' => ('已确认', Colors.green),
      'cancelled' => ('已取消', Colors.grey),
      _ => ('待确认', Colors.orange),
    };
    return Text(label, style: TextStyle(color: color));
  }

  String _transactionSummary(Map<String, dynamic> item) {
    if (item['status'] == 'pending') {
      return '待确认：${item['pendingReason'] ?? '正式净值尚未公布'}';
    }
    final amount = item['entryMode'] == 'shares'
        ? '按份额'
        : _money(item['amount']);
    return '$amount · ${_number(item['shares']).toStringAsFixed(2)} 份';
  }
}

double _number(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
String _money(dynamic value) =>
    value == null ? '—' : '¥${_number(value).toStringAsFixed(2)}';
String _rate(dynamic value) =>
    value == null ? '—' : '${(_number(value) * 100).toStringAsFixed(2)}%';
String _shares(dynamic value) => _number(value).toStringAsFixed(2);
