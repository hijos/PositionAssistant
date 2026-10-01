import 'dart:async';

import 'package:flutter/material.dart';

import 'data/transaction_repository.dart';

/// Shared confirmation step for permanent deletes; returns true only when the
/// user explicitly confirms.
Future<bool> confirmPermanentDelete(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '删除',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed == true;
}

String _errorText(Object error) => '$error'
    .replaceFirst('Exception: ', '')
    .replaceFirst('FormatException: ', '');

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

/// Rendering state of the 清理已取消交易 action, published by
/// [TransactionHistoryPage] when a host renders the button outside the page.
typedef TransactionCleanupState = ({bool busy, bool hasCancelled});

class TransactionHistoryPage extends StatefulWidget {
  const TransactionHistoryPage({
    required this.repository,
    this.fundCode,
    this.pageTitle = '交易记录',
    this.embedded = false,
    this.cleanupState,
    super.key,
  });

  final TransactionRepository repository;
  final String? fundCode;
  final String pageTitle;
  final bool embedded;

  /// When set, the embedded page leaves the cleanup button to its host (the
  /// home shell shows it in the app bar, in the same slot as the watchlist
  /// tab's add button) and publishes its enabled/busy state here.
  final ValueNotifier<TransactionCleanupState>? cleanupState;

  @override
  State<TransactionHistoryPage> createState() => TransactionHistoryPageState();
}

class TransactionHistoryPageState extends State<TransactionHistoryPage> {
  late Future<List<Map<String, dynamic>>> records;
  List<Map<String, dynamic>> items = const [];
  bool loading = true;
  String? error;
  bool busy = false;

  /// Every visual change below goes through setState, so this is the single
  /// place that keeps an externally hosted cleanup button in sync.
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    final target = widget.cleanupState;
    if (target == null) return;
    final next = (busy: busy, hasCancelled: _cancelled.isNotEmpty);
    if (target.value != next) target.value = next;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(TransactionHistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different filter or data source must be re-read, not shown stale.
    if (oldWidget.repository != widget.repository ||
        oldWidget.fundCode != widget.fundCode) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final result = widget.repository.list();
    records = result;
    if (loading != true || error != null) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final data = await result;
      if (!mounted || !identical(result, records)) return;
      setState(() {
        items = data
            .where(
              (item) =>
                  widget.fundCode == null ||
                  item['fundCode'] == widget.fundCode,
            )
            .toList();
        loading = false;
        error = null;
      });
    } catch (exception) {
      if (!mounted || !identical(result, records)) return;
      setState(() {
        loading = false;
        error = '$exception';
      });
    }
  }

  void reload() => unawaited(_load());

  List<Map<String, dynamic>> get _cancelled => items
      .where((item) => item['status'] == 'cancelled')
      .toList(growable: false);

  Future<void> confirm() async {
    try {
      final confirmed = await widget.repository.confirmPending();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              confirmed.isEmpty
                  ? '暂无可确认交易，仍需对应交易日正式净值'
                  : '已确认 ${confirmed.length} 笔交易',
            ),
          ),
        );
        reload();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('确认失败，请稍后重试')));
      }
    }
  }

  /// Clears cancelled records for this page's scope.
  ///
  /// The unfiltered history page clears everything the repository holds. A
  /// fund-filtered page would otherwise delete other funds' records while only
  /// reporting its own count, so it deletes just the records it displays.
  Future<int> _clearScope(List<Map<String, dynamic>> cancelled) async {
    if (widget.fundCode == null) return widget.repository.clearCancelled();
    for (final item in cancelled) {
      await widget.repository.deleteCancelled('${item['id']}');
    }
    return cancelled.length;
  }

  Future<void> clearCancelled() async {
    final cancelled = _cancelled;
    if (busy || cancelled.isEmpty) return;
    final confirmed = await confirmPermanentDelete(
      context,
      title: '清理已取消交易',
      message: '确定删除全部 ${cancelled.length} 条已取消交易吗？删除后无法恢复。',
      confirmLabel: '删除全部',
    );
    if (!confirmed || !mounted) return;
    setState(() => busy = true);
    try {
      final deleted = await _clearScope(cancelled);
      if (!mounted) return;
      setState(() => busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已清理 $deleted 条已取消交易')));
      reload();
    } catch (exception) {
      if (!mounted) return;
      setState(() => busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('清理失败：${_errorText(exception)}')));
    }
  }

  Future<void> openMenu(Map<String, dynamic> item) async {
    if (item['status'] != 'cancelled') return;
    final remove = await showModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                '${item['fundName'] ?? item['fundCode']} · ${item['type'] == 'buy' ? '买入' : '卖出'}',
              ),
              subtitle: Text('${item['date'] ?? '未记录'} · 已取消'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_forever_outlined),
              title: const Text('删除交易'),
              onTap: () => Navigator.of(sheetContext).pop(true),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('取消'),
              onTap: () => Navigator.of(sheetContext).pop(false),
            ),
          ],
        ),
      ),
    );
    if (remove != true || !mounted) return;
    await deleteCancelled(item);
  }

  Future<void> deleteCancelled(Map<String, dynamic> item) async {
    if (busy) return;
    final confirmed = await confirmPermanentDelete(
      context,
      title: '删除交易记录？',
      message: '这条已取消交易将被永久删除，无法恢复。',
    );
    if (!confirmed || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.repository.deleteCancelled('${item['id']}');
      if (!mounted) return;
      setState(() => busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('交易记录已删除')));
      reload();
    } catch (exception) {
      if (!mounted) return;
      setState(() => busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败：${_errorText(exception)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cancelled = _cancelled;
    final action = IconButton(
      onPressed: busy || cancelled.isEmpty ? null : clearCancelled,
      tooltip: '清理已取消交易',
      icon: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.delete_sweep_outlined),
    );
    final body = loading
        ? const Center(child: CircularProgressIndicator())
        : error != null && items.isEmpty
        ? Center(
            child: FilledButton(
              onPressed: reload,
              child: const Text('读取失败，点击重试'),
            ),
          )
        : _list(sortTransactions(items));
    if (!widget.embedded) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.pageTitle), actions: [action]),
        body: body,
      );
    }
    // With a host-provided notifier the cleanup action lives in the host's
    // app bar; otherwise the embedded page keeps it in a row above the list.
    if (widget.cleanupState != null) return body;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [action],
          ),
        ),
        Expanded(child: body),
      ],
    );
  }

  Widget _list(List<Map<String, dynamic>> sorted) {
    if (sorted.isEmpty) return const Center(child: Text('暂无交易记录'));
    final pending = sorted
        .where((item) => item['status'] == 'pending')
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (pending.isNotEmpty)
          FilledButton.icon(
            onPressed: confirm,
            icon: const Icon(Icons.refresh),
            label: Text('重新确认待确认交易（${pending.length}）'),
          ),
        for (final item in sorted)
          Card(
            child: ListTile(
              title: Text(
                '${item['fundName'] ?? item['fundCode']} · ${item['type'] == 'buy' ? '买入' : '卖出'}',
              ),
              subtitle: Text(_summary(item)),
              trailing: _status(item['status']),
              onLongPress: item['status'] == 'cancelled'
                  ? () => openMenu(item)
                  : null,
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
  }

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

class TransactionDetailPage extends StatefulWidget {
  const TransactionDetailPage({
    required this.transaction,
    required this.repository,
    super.key,
  });

  final Map<String, dynamic> transaction;
  final TransactionRepository repository;

  @override
  State<TransactionDetailPage> createState() => _TransactionDetailPageState();
}

class _TransactionDetailPageState extends State<TransactionDetailPage> {
  bool busy = false;

  Future<void> _cancel() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.repository.cancel('${widget.transaction['id']}');
      if (!mounted) return;
      setState(() => busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('交易已撤销，账本已重算')));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('撤销失败：${_errorText(error)}')));
    }
  }

  Future<void> _delete() async {
    if (busy) return;
    final confirmed = await confirmPermanentDelete(
      context,
      title: '删除交易记录？',
      message: '这条已取消交易将被永久删除，无法恢复。',
    );
    if (!confirmed || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.repository.deleteCancelled('${widget.transaction['id']}');
      if (!mounted) return;
      setState(() => busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('交易记录已删除')));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('删除失败：${_errorText(error)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.transaction;
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
              (
                '录入方式',
                switch (item['entryMode']) {
                  'shares' => '按份额',
                  'holding' =>
                    item['holdingProfit'] != null
                        ? '按持有金额和持有收益'
                        : '按持有金额和持有收益率',
                  _ => '按金额',
                },
              ),
              if (item['entryMode'] == 'holding') ...[
                ('持有金额', _number(item['holdingAmount'])),
                if (item['holdingProfit'] != null)
                  ('持有收益', _inputNumber(item['holdingProfit']))
                else
                  (
                    '持有收益率（原始输入）',
                    _inputNumber(item['holdingReturnRate'], suffix: '%'),
                  ),
                ('持有成本', '${_number(item['amount'])}（计算所得）'),
                ('交易份额', '${_number(item['shares'])}（计算所得）'),
              ] else ...[
                ('交易金额', _number(item['amount'])),
                ('交易份额', _number(item['shares'])),
              ],
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
          if (status == 'cancelled' && item['id'] != null)
            FilledButton.icon(
              onPressed: busy ? null : _delete,
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text('删除交易'),
            )
          else if (item['id'] != null)
            FilledButton.icon(
              onPressed: busy ? null : _cancel,
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

  String _inputNumber(dynamic value, {String suffix = ''}) =>
      value == null ? '未记录' : '$value$suffix';

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
