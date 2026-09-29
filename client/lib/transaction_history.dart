import 'package:flutter/material.dart';

import 'data/transaction_repository.dart';

List<Map<String, dynamic>> sortTransactions(
  Iterable<Map<String, dynamic>> records,
) {
  final sorted = records.toList();
  int compare(Map<String, dynamic> a, Map<String, dynamic> b) {
    final date = '${b['date'] ?? ''}'.compareTo('${a['date'] ?? ''}');
    if (date != 0) return date;
    final cutoff = (b['cutoff'] == 'after' ? 1 : 0).compareTo(
      a['cutoff'] == 'after' ? 1 : 0,
    );
    if (cutoff != 0) return cutoff;
    final created = '${b['createdAt'] ?? ''}'.compareTo(
      '${a['createdAt'] ?? ''}',
    );
    if (created != 0) return created;
    return '${b['id'] ?? ''}'.compareTo('${a['id'] ?? ''}');
  }

  sorted.sort(compare);
  return sorted;
}

class TransactionHistoryPage extends StatefulWidget {
  const TransactionHistoryPage({
    required this.repository,
    this.fundCode,
    this.pageTitle = '交易记录',
    super.key,
  });

  final TransactionRepository repository;
  final String? fundCode;
  final String pageTitle;

  @override
  State<TransactionHistoryPage> createState() => _TransactionHistoryPageState();
}

class _TransactionHistoryPageState extends State<TransactionHistoryPage> {
  late Future<List<Map<String, dynamic>>> records = widget.repository.list();

  void reload() {
    setState(() {
      records = widget.repository.list();
    });
  }

  Future<void> confirm() async {
    try {
      final confirmed = await widget.repository.confirmPending();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(confirmed.isEmpty ? '暂无可确认交易，仍需对应交易日正式净值' : '已确认 ${confirmed.length} 笔交易')));
        reload();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('确认失败，请稍后重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.pageTitle)),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: records,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: FilledButton(
              onPressed: reload,
              child: const Text('读取失败，点击重试'),
            ),
          );
        }
        final items = sortTransactions(
          (snapshot.data ?? const <Map<String, dynamic>>[]).where(
            (item) =>
                widget.fundCode == null || item['fundCode'] == widget.fundCode,
          ),
        );
        final pending = items
            .where((item) => item['status'] == 'pending')
            .toList();
        if (items.isEmpty) {
          return const Center(child: Text('暂无交易记录'));
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (pending.isNotEmpty)
              FilledButton.icon(
                onPressed: confirm,
                icon: const Icon(Icons.refresh),
                label: Text('重新确认待确认交易（${pending.length}）'),
              ),
            for (final item in items)
              Card(
                child: ListTile(
                  title: Text(
                    '${item['fundName'] ?? item['fundCode']} · ${item['type'] == 'buy' ? '买入' : '卖出'}',
                  ),
                  subtitle: Text(_summary(item)),
                  trailing: _status(item['status']),
                  onTap: () async {
                    final changed = await Navigator.of(context).push<bool>(
                      MaterialPageRoute<bool>(
                        builder: (_) => TransactionDetailPage(
                          transaction: item,
                          repository: widget.repository,
                        ),
                      ),
                    );
                    if (changed == true && mounted) reload();
                  },
                ),
              ),
          ],
        );
      },
    ),
  );

  String _summary(Map<String, dynamic> item) {
    final status = item['status'];
    if (status == 'pending') {
      return '待确认：${item['pendingReason'] ?? '正式净值尚未公布'}';
    }
    final date = item['date'] ?? '未记录操作日期';
    final navDate = item['navDate'] ?? '未记录净值日期';
    return '$date · 净值日期 $navDate';
  }

  Widget _status(dynamic status) {
    final (label, color) = switch (status) {
      'confirmed' => ('已确认', Colors.green),
      'cancelled' => ('已取消', Colors.grey),
      _ => ('待确认', Colors.orange),
    };
    return Text(label, style: TextStyle(color: color));
  }
}

class TransactionDetailPage extends StatelessWidget {
  const TransactionDetailPage({
    required this.transaction,
    required this.repository,
    super.key,
  });

  final Map<String, dynamic> transaction;
  final TransactionRepository repository;

  Future<void> _cancel(BuildContext context) async {
    try {
      await repository.cancel('${transaction['id']}');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('交易已撤销，账本已重算')));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!context.mounted) return;
      final message = '$error'.replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('撤销失败：$message')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = transaction;
    final isBuy = item['type'] == 'buy';
    final status = item['status'];
    return Scaffold(
      appBar: AppBar(title: const Text('交易详情')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(
            context,
            '基金',
            _rows([
              ('基金名称', item['fundName'] ?? item['fundCode'] ?? '未记录'),
              ('基金代码', item['fundCode'] ?? '未记录'),
              ('份额类别', item['fundType'] ?? '未记录'),
            ]),
          ),
          _section(
            context,
            '交易',
            _rows([
              ('交易方向', isBuy ? '买入' : '卖出'),
              ('录入方式', item['entryMode'] == 'shares' ? '按份额' : '按金额'),
              ('交易金额', _number(item['amount'])),
              ('交易份额', _number(item['shares'])),
              ('操作日期', item['date'] ?? '未记录'),
              ('操作时间', item['cutoff'] == 'after' ? '15:00 后' : '15:00 前'),
            ]),
          ),
          _section(
            context,
            '费用',
            _rows([
              ('费用方式', item['feeMode'] == 'fixed' ? '固定费用' : '费率'),
              ('手续费率', _number(item['feeRate'], suffix: '%')),
              ('固定费用', _number(item['fixedFee'])),
              ('实际手续费', _number(item['fee'])),
            ]),
          ),
          _section(
            context,
            '净值与状态',
            _rows([
              ('成交净值', _number(item['tradeNav'] ?? item['nav'])),
              ('净值日期', item['navDate'] ?? '未记录'),
              ('状态', _statusLabel(status)),
              if (status == 'pending')
                ('待确认原因', item['pendingReason'] ?? '正式净值尚未公布'),
              if (status == 'cancelled') ('取消时间', item['cancelledAt'] ?? '未记录'),
            ]),
          ),
          _section(
            context,
            '备注与来源',
            _rows([('备注', _text(item['note'])), ('来源', _text(item['source']))]),
          ),
          _section(
            context,
            '记录信息',
            _rows([
              ('记录编号', _text(item['id'])),
              ('创建时间', _text(item['createdAt'])),
              ('幂等请求号', _text(item['clientRequestId'])),
            ]),
          ),
          if (status != 'cancelled' && transaction['id'] != null)
            FilledButton.icon(
              onPressed: () => _cancel(context),
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('撤销交易'),
            ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, Widget child) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          child,
        ],
      ),
    ),
  );

  Widget _rows(List<(String, String)> entries) => Column(
    children: [
      for (final entry in entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 96, child: Text(entry.$1)),
              Expanded(child: Text(entry.$2)),
            ],
          ),
        ),
    ],
  );

  String _number(dynamic value, {String suffix = ''}) {
    if (value == null || '$value' == '0' || '$value' == '0.0') {
      return '—';
    }
    return '$value$suffix';
  }

  String _text(dynamic value) {
    final text = '$value';
    return value == null || text.isEmpty ? '—' : text;
  }

  String _statusLabel(dynamic value) => switch (value) {
    'confirmed' => '已确认',
    'cancelled' => '已取消',
    _ => '待确认',
  };
}
