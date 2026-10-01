import 'package:flutter/material.dart';

import 'data/transaction_repository.dart';

class TransactionEntryPage extends StatefulWidget {
  const TransactionEntryPage({
    required this.funds,
    required this.repository,
    this.onSearchAndAdd,
    this.initialType = 'buy',
    super.key,
  });
  final List<Map<String, dynamic>> funds;
  final TransactionRepository repository;
  final Future<List<Map<String, dynamic>>> Function()? onSearchAndAdd;
  final String initialType;

  @override
  State<TransactionEntryPage> createState() => _TransactionEntryPageState();
}

class _TransactionEntryPageState extends State<TransactionEntryPage> {
  late List<Map<String, dynamic>> funds;
  late final TextEditingController value = TextEditingController(text: '100');
  late final TextEditingController holdingProfit = TextEditingController(
    text: '0',
  );
  late final TextEditingController fee = TextEditingController(text: '0');
  late final TextEditingController note = TextEditingController();
  late final TextEditingController source = TextEditingController();
  String? fundCode;
  late String transactionType;
  String entryMode = 'amount';
  String feeMode = 'rate';
  String cutoff = 'before';
  late String date;
  bool busy = false;
  Map<String, dynamic>? previewResult;
  String? error;
  late final String clientRequestId =
      'client-${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';

  @override
  void initState() {
    super.initState();
    funds = List<Map<String, dynamic>>.of(widget.funds);
    transactionType = ['buy', 'sell'].contains(widget.initialType)
        ? widget.initialType
        : 'buy';
    fundCode = funds.isEmpty ? null : funds.first['code'] as String;
    final now = DateTime.now();
    date =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic>? get selectedFund {
    for (final fund in funds) {
      if (fund['code'] == fundCode) return fund;
    }
    return null;
  }

  Future<void> searchAndAddFund() async {
    final callback = widget.onSearchAndAdd;
    if (callback == null || busy) return;
    final oldCodes = funds
        .map((fund) => fund['code'])
        .whereType<String>()
        .toSet();
    final updated = await callback();
    if (!mounted) return;
    final next = List<Map<String, dynamic>>.of(updated);
    final added = next.where((fund) {
      final code = fund['code'];
      return code is String && !oldCodes.contains(code);
    }).toList();
    setState(() {
      funds = next;
      if (added.isNotEmpty) fundCode = added.last['code'] as String;
      previewResult = null;
      error = null;
    });
  }

  Map<String, dynamic> draft() {
    final fund = selectedFund;
    if (fund == null) throw const FormatException('请先选择基金');
    return {
      'fundCode': fund['code'],
      'fundName': fund['name'],
      'fundType': fund['type'],
      'type': transactionType,
      'entryMode': entryMode,
      'amount': entryMode == 'amount' ? value.text.trim() : 0,
      'shares': entryMode == 'shares' ? value.text.trim() : 0,
      'holdingAmount': entryMode == 'holding' ? value.text.trim() : 0,
      'holdingProfit': entryMode == 'holding' ? holdingProfit.text.trim() : 0,
      'feeMode': feeMode,
      'feeRate': feeMode == 'rate' ? fee.text.trim() : 0,
      'fixedFee': feeMode == 'fixed' ? fee.text.trim() : 0,
      'date': date,
      'cutoff': cutoff,
      'note': note.text,
      'source': source.text,
      'clientRequestId': clientRequestId,
    };
  }

  void changed() {
    if (previewResult != null || error != null) {
      setState(() {
        previewResult = null;
        error = null;
      });
    }
  }

  Future<void> preview() async {
    setState(() {
      busy = true;
      error = null;
      previewResult = null;
    });
    try {
      final result = await widget.repository.preview(draft());
      if (!mounted) return;
      setState(() => previewResult = result);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => error = e is FormatException ? e.message : '预览失败，请检查输入或网络',
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (previewResult == null) {
      await preview();
      if (!mounted || previewResult == null) return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.repository.create(draft());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['status'] == 'pending'
                ? '${transactionType == 'buy' ? '买入' : '卖出'}已保存，等待净值确认'
                : '${transactionType == 'buy' ? '买入' : '卖出'}已保存',
          ),
        ),
      );
      Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => error = e is FormatException ? e.message : '保存失败，请检查登录或网络后重试',
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('交易录入')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (funds.isEmpty)
          const TransactionSectionCard(
            title: '暂无可用基金',
            description: '请先在基金搜索与添加中添加基金，再录入交易。',
          ),
        if (funds.isEmpty &&
            widget.onSearchAndAdd != null &&
            transactionType == 'buy')
          OutlinedButton.icon(
            onPressed: busy ? null : searchAndAddFund,
            icon: const Icon(Icons.search),
            label: const Text('搜索基金并添加到自选列表'),
          ),
        if (funds.isNotEmpty) ...[
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '交易方向',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment<String>(
                          value: 'buy',
                          label: Text('买入'),
                          icon: Icon(Icons.add_circle_outline, size: 18),
                        ),
                        ButtonSegment<String>(
                          value: 'sell',
                          label: Text('卖出'),
                          icon: Icon(Icons.remove_circle_outline, size: 18),
                        ),
                      ],
                      selected: {transactionType},
                      onSelectionChanged: busy
                          ? null
                          : (selection) {
                              setState(() {
                                transactionType = selection.first;
                                if (transactionType == 'sell' &&
                                    entryMode == 'holding') {
                                  entryMode = 'amount';
                                }
                                previewResult = null;
                              });
                            },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '交易基金',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: fundCode,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    items: [
                      for (final fund in funds)
                        DropdownMenuItem(
                          value: fund['code'] as String,
                          child: Text(
                            '${fund['name']} · ${fund['code']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: busy
                        ? null
                        : (value) {
                            setState(() {
                              fundCode = value;
                              previewResult = null;
                            });
                          },
                  ),
                  if (widget.onSearchAndAdd != null &&
                      transactionType == 'buy') ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: busy ? null : searchAndAddFund,
                        icon: const Icon(Icons.search, size: 16),
                        label: const Text('搜索基金并添加到自选列表'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    '录入方式',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: entryMode,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'amount', child: Text('按金额录入')),
                      DropdownMenuItem(value: 'shares', child: Text('按份额录入')),
                      DropdownMenuItem(
                        value: 'holding',
                        child: Text('按持有金额和持有收益录入'),
                      ),
                    ],
                    onChanged: busy
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() {
                              entryMode = value;
                              if (entryMode == 'holding')
                                transactionType = 'buy';
                              previewResult = null;
                            });
                          },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entryMode == 'amount'
                        ? '${transactionType == 'buy' ? '买入' : '卖出'}金额（${transactionType == 'sell' ? '扣费前' : '含手续费'}）'
                        : entryMode == 'shares'
                        ? '${transactionType == 'buy' ? '买入' : '卖出'}份额'
                        : '当前持有金额',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: value,
                    enabled: !busy,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      prefixText: entryMode == 'shares' ? null : '￥ ',
                      suffixText: entryMode == 'shares' ? '份' : '元',
                    ),
                    onChanged: (_) => changed(),
                  ),
                  if (entryMode == 'holding') ...[
                    const SizedBox(height: 16),
                    Text(
                      '持有收益',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: holdingProfit,
                      enabled: !busy,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        prefixText: '￥ ',
                        suffixText: '元',
                      ),
                      onChanged: (_) => changed(),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '份额 = 持有金额 ÷ 最新正式净值；持有成本 = 持有金额 - 持有收益。亏损请输入负数。',
                    ),
                  ],
                  if (entryMode != 'holding') ...[
                    const SizedBox(height: 16),
                    Text(
                      '手续费',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: DropdownButtonFormField<String>(
                            initialValue: feeMode,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 12,
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'rate',
                                child: Text('费率 %'),
                              ),
                              DropdownMenuItem(
                                value: 'fixed',
                                child: Text('固定费用 元'),
                              ),
                            ],
                            onChanged: busy
                                ? null
                                : (value) {
                                    if (value == null) return;
                                    setState(() {
                                      feeMode = value;
                                      fee.text = '0';
                                      previewResult = null;
                                    });
                                  },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 6,
                          child: TextField(
                            controller: fee,
                            enabled: !busy,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              suffixText: feeMode == 'rate' ? '%' : '元',
                            ),
                            onChanged: (_) => changed(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '成交确认时间',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 6,
                        child: OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate:
                                        DateTime.tryParse(date) ??
                                        DateTime.now(),
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime.now(),
                                  );
                                  if (picked == null || !mounted) return;
                                  setState(() {
                                    date =
                                        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                                    previewResult = null;
                                  });
                                },
                          icon: const Icon(
                            Icons.calendar_today_outlined,
                            size: 16,
                          ),
                          label: Text(date),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 5,
                        child: DropdownButtonFormField<String>(
                          initialValue: cutoff,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 12,
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'before',
                              child: Text('15:00 前'),
                            ),
                            DropdownMenuItem(
                              value: 'after',
                              child: Text('15:00 后'),
                            ),
                          ],
                          onChanged: busy
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  setState(() {
                                    cutoff = value;
                                    previewResult = null;
                                  });
                                },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '备注（可选）',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: note,
                    enabled: !busy,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    onChanged: (_) => changed(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '来源（可选）',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: source,
                    enabled: !busy,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    onChanged: (_) => changed(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (previewResult != null) _PreviewCard(result: previewResult!),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : preview,
                  child: Text(
                    busy
                        ? '处理中…'
                        : '预览${transactionType == 'buy' ? '买入' : '卖出'}',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : save,
                  child: Text('保存${transactionType == 'buy' ? '买入' : '卖出'}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ],
    ),
  );

  @override
  void dispose() {
    value.dispose();
    holdingProfit.dispose();
    fee.dispose();
    note.dispose();
    source.dispose();
    super.dispose();
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.result});
  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final pending = result['status'] == 'pending';
    final lines = <String>[
      if (result['navDate'] != null) '净值日期：${result['navDate']}',
      if (result['nav'] != null) '成交净值：${result['nav']}',
      if (result['shares'] != null && result['shares'] != 0)
        '预计份额：${result['shares']}',
      if (result['amount'] != null && result['amount'] != 0)
        '交易金额：${result['amount']}',
      if (result['fee'] != null) '手续费：${result['fee']}',
      if (pending) '待确认：${result['pendingReason'] ?? '正式净值尚未公布'}',
    ];
    return Card(
      margin: EdgeInsets.zero,
      color: pending
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${result['type'] == 'sell' ? '卖出' : '买入'}预览',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final line in lines) Text(line),
          ],
        ),
      ),
    );
  }
}

class TransactionSectionCard extends StatelessWidget {
  const TransactionSectionCard({
    required this.title,
    required this.description,
    super.key,
  });
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(description, style: const TextStyle(height: 1.8)),
        ],
      ),
    ),
  );
}
