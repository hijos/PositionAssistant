import 'package:flutter/material.dart';

import 'data/offline_repository.dart';
import 'data/repository.dart';

class LocalPlansPage extends StatefulWidget {
  const LocalPlansPage({
    required this.open,
    this.fundsFuture,
    this.onSearchAndAdd,
    super.key,
  });
  final Future<Repository> Function() open;
  final Future<List<Map<String, dynamic>>> Function()? fundsFuture;
  final Future<List<Map<String, dynamic>>> Function()? onSearchAndAdd;
  @override
  State<LocalPlansPage> createState() => _LocalPlansPageState();
}

class _LocalPlansPageState extends State<LocalPlansPage> {
  late final LocalPlanRepository repository = LocalPlanRepository(widget.open);
  late Future<List<Map<String, dynamic>>> plans = _loadPlans();

  Future<List<Map<String, dynamic>>> _loadPlans() async {
    final items = await repository.list();
    await repository.generateDueEntries();
    return items;
  }

  void reload() => setState(() {
    plans = _loadPlans();
  });

  Future<void> deletePlan(Map<String, dynamic> plan) async {
    final selected = await showModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text('${plan['fundName']} · ${plan['fundCode']}')),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(sheetContext).colorScheme.error,
              ),
              title: Text(
                '删除定投计划',
                style: TextStyle(
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
              ),
              onTap: () => Navigator.pop(sheetContext, true),
            ),
            ListTile(
              title: const Text('取消'),
              onTap: () => Navigator.pop(sheetContext, false),
            ),
          ],
        ),
      ),
    );
    if (selected != true || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除定投计划？'),
        content: Text(
          '确定删除“${plan['fundName']}”的定投计划及全部期次记录吗？'
          '已生成的交易记录会保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await repository.deletePlan('${plan['id']}');
      if (!mounted) return;
      reload();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('定投计划已删除')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> createPlan() async {
    var availableFunds = <Map<String, dynamic>>[];
    try {
      availableFunds = await widget.fundsFuture?.call() ?? [];
    } catch (_) {
      // The code/name fields below remain available when the fund list is
      // temporarily unavailable.
    }
    if (!mounted) return;
    final code = TextEditingController(text: '000001');
    final name = TextEditingController(text: '本地基金');
    final value = TextEditingController(text: '100');
    final fee = TextEditingController(text: '0');
    final date = TextEditingController(text: _today());
    final note = TextEditingController();
    var selectedCode = availableFunds.isEmpty
        ? null
        : '${availableFunds.first['code']}';
    var selectedFundType = availableFunds.isEmpty
        ? ''
        : '${availableFunds.first['type'] ?? ''}';
    if (selectedCode != null) {
      code.text = selectedCode;
      name.text = '${availableFunds.first['name']}';
    }
    var transactionType = 'buy';
    var entryMode = 'amount';
    var feeMode = 'rate';
    var cutoff = 'before';
    var cycle = 'monthly';
    var day = 1;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 24,
          ),
          title: const Text('新建定投计划'),
          content: SizedBox(
            width: screenWidth > 720 ? 640 : screenWidth - 24,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                      onSelectionChanged: (selection) => setDialogState(() {
                        transactionType = selection.first;
                      }),
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
                  if (availableFunds.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: selectedCode,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final fund in availableFunds)
                          DropdownMenuItem(
                            value: '${fund['code']}',
                            child: Text(
                              '${fund['name']} · ${fund['code']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) => setDialogState(() {
                        selectedCode = value;
                        final fund = availableFunds.firstWhere(
                          (item) => '${item['code']}' == value,
                          orElse: () => const <String, dynamic>{},
                        );
                        if (fund.isNotEmpty) {
                          code.text = '${fund['code']}';
                          name.text = '${fund['name']}';
                          selectedFundType = '${fund['type'] ?? ''}';
                        }
                      }),
                    )
                  else ...[
                    TextField(
                      controller: code,
                      decoration: const InputDecoration(labelText: '基金代码'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(labelText: '基金名称'),
                    ),
                  ],
                  if (widget.onSearchAndAdd != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () async {
                          final updated = await widget.onSearchAndAdd!();
                          if (!mounted) return;
                          setDialogState(() {
                            availableFunds = List<Map<String, dynamic>>.of(
                              updated,
                            );
                            if (availableFunds.isNotEmpty) {
                              final fund = availableFunds.last;
                              selectedCode = '${fund['code']}';
                              code.text = selectedCode ?? '';
                              name.text = '${fund['name']}';
                              selectedFundType = '${fund['type'] ?? ''}';
                            }
                          });
                        },
                        icon: const Icon(Icons.search, size: 18),
                        label: const Text('搜索基金并添加到自选列表'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
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
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'amount',
                        child: Text(
                          '按${transactionType == 'buy' ? '买入' : '卖出'}金额和${transactionType == 'buy' ? '买入' : '卖出'}时间',
                        ),
                      ),
                    ],
                    onChanged: (value) => setDialogState(() {
                      entryMode = value ?? entryMode;
                    }),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: value,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: entryMode == 'amount'
                          ? '${transactionType == 'buy' ? '买入' : '卖出'}金额（${transactionType == 'buy' ? '含手续费' : '扣费前'}）'
                          : '${transactionType == 'buy' ? '买入' : '卖出'}份额',
                      border: const OutlineInputBorder(),
                      suffixText: entryMode == 'amount' ? '元' : '份',
                    ),
                  ),
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
                          onChanged: (value) => setDialogState(() {
                            feeMode = value ?? feeMode;
                            fee.text = '0';
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 6,
                        child: TextField(
                          controller: fee,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            suffixText: feeMode == 'rate' ? '%' : '元',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '起始日期与执行规则',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: date,
                    decoration: const InputDecoration(
                      labelText: '起始日期（YYYY-MM-DD）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: cycle,
                    decoration: const InputDecoration(
                      labelText: '定投周期',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'daily', child: Text('每天')),
                      DropdownMenuItem(value: 'weekly', child: Text('每周')),
                      DropdownMenuItem(value: 'monthly', child: Text('每月')),
                    ],
                    onChanged: (value) => setDialogState(() {
                      cycle = value ?? cycle;
                      if (cycle == 'daily') day = 1;
                      if (cycle == 'weekly' && day > 7) day = 1;
                    }),
                  ),
                  if (cycle != 'daily') ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      key: ValueKey(cycle),
                      initialValue: day,
                      decoration: const InputDecoration(
                        labelText: '执行日',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (var i = 1; i <= (cycle == 'weekly' ? 7 : 31); i++)
                          DropdownMenuItem(value: i, child: Text('执行日 $i')),
                      ],
                      onChanged: (value) => setDialogState(() {
                        day = value ?? day;
                      }),
                    ),
                  ],
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: cutoff,
                    decoration: const InputDecoration(
                      labelText: '成交确认时间',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'before', child: Text('15:00 前')),
                      DropdownMenuItem(value: 'after', child: Text('15:00 后')),
                    ],
                    onChanged: (value) => setDialogState(() {
                      cutoff = value ?? cutoff;
                    }),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: note,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: '备注（可选）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const InputDecorator(
                    decoration: InputDecoration(
                      labelText: '来源',
                      border: OutlineInputBorder(),
                    ),
                    child: Text('定投计划'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    final planCode = code.text.trim();
    final planName = name.text.trim();
    final planValue = value.text.trim();
    final planDate = date.text.trim();
    final planNote = note.text;
    final planFee = fee.text.trim();
    final planType = selectedFundType;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    code.dispose();
    name.dispose();
    value.dispose();
    fee.dispose();
    date.dispose();
    note.dispose();
    if (ok != true || !mounted) return;
    try {
      await repository.create(
        fundCode: planCode,
        fundName: planName,
        fundType: planType,
        mode: entryMode,
        value: double.parse(planValue),
        cycle: cycle,
        startDate: planDate,
        executionDay: day,
        transactionType: transactionType,
        feeMode: feeMode,
        feeRate: feeMode == 'rate' ? double.parse(planFee) : 0,
        fixedFee: feeMode == 'fixed' ? double.parse(planFee) : 0,
        cutoff: cutoff,
        note: planNote,
      );
      reload();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('定投计划')),
    floatingActionButton: FloatingActionButton(
      onPressed: createPlan,
      child: const Icon(Icons.add),
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: plans,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return Center(
            child: TextButton(
              onPressed: reload,
              child: const Text('定投读取失败，点击重试'),
            ),
          );
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final items = snapshot.data!;
        if (items.isEmpty) return const Center(child: Text('暂无定投计划'));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final plan in items)
              Card(
                child: ListTile(
                  onLongPress: () => deletePlan(plan),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => LocalPlanEntriesPage(
                        repository: repository,
                        plan: plan,
                      ),
                    ),
                  ),
                  title: Text('${plan['fundName']} · ${plan['fundCode']}'),
                  subtitle: Text(
                    '${_cycleLabel('${plan['cycle']}')}'
                    '${plan['cycle'] == 'daily' ? '' : ' · 执行日 ${plan['executionDay']}'}'
                    ' · ${plan['type'] == 'sell' ? '卖出' : '买入'}'
                    ' · ${plan['mode'] == 'shares' ? '${plan['shares']} 份' : '${plan['amount']} 元'}'
                    ' · 来源：定投计划'
                    ' · ${plan['enabled'] == true ? '启用' : '暂停'}',
                  ),
                  trailing: Switch(
                    value: plan['enabled'] == true,
                    onChanged: (v) async {
                      await repository.setEnabled('${plan['id']}', v);
                      reload();
                    },
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class LocalQuotaPage extends StatefulWidget {
  const LocalQuotaPage({required this.open, super.key});
  final Future<Repository> Function() open;
  @override
  State<LocalQuotaPage> createState() => _LocalQuotaPageState();
}

class _LocalQuotaPageState extends State<LocalQuotaPage> {
  late final LocalQuotaRepository repository = LocalQuotaRepository(
    widget.open,
  );
  late Future<List<Map<String, dynamic>>> quotas = repository.list();
  void reload() => setState(() {
    quotas = repository.list();
  });
  Future<void> edit() async {
    final code = TextEditingController(text: '000001');
    final name = TextEditingController(text: '本地基金');
    final status = TextEditingController(text: '开放');
    final limit = TextEditingController(text: '1000');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加或修改额度'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: code,
              decoration: const InputDecoration(labelText: '基金代码'),
            ),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: '基金名称'),
            ),
            TextField(
              controller: status,
              decoration: const InputDecoration(labelText: '申购状态'),
            ),
            TextField(
              controller: limit,
              decoration: const InputDecoration(labelText: '单日限额'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await repository.save(
        code: code.text.trim(),
        name: name.text.trim(),
        category: 'QDII',
        status: status.text,
        limit: limit.text,
      );
      reload();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('额度列表')),
    floatingActionButton: FloatingActionButton(
      onPressed: edit,
      child: const Icon(Icons.edit),
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: quotas,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return Center(
            child: TextButton(
              onPressed: reload,
              child: const Text('额度读取失败，点击重试'),
            ),
          );
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final items = snapshot.data!;
        if (items.isEmpty) return const Center(child: Text('暂无额度数据'));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final item in items)
              Card(
                child: ListTile(
                  title: Text('${item['name']} · ${item['code']}'),
                  subtitle: Text('${item['status']} · 单日限额 ${item['limit']}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.restore),
                    onPressed: () async {
                      await repository.restore('${item['code']}');
                      reload();
                    },
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class LocalPlanEntriesPage extends StatefulWidget {
  const LocalPlanEntriesPage({
    required this.repository,
    required this.plan,
    super.key,
  });
  final LocalPlanRepository repository;
  final Map<String, dynamic> plan;
  @override
  State<LocalPlanEntriesPage> createState() => _LocalPlanEntriesPageState();
}

class _LocalPlanEntriesPageState extends State<LocalPlanEntriesPage> {
  late Future<List<Map<String, dynamic>>> records = _loadRecords();
  bool busy = false;
  String? error;

  Future<List<Map<String, dynamic>>> _loadRecords() async {
    final planId = '${widget.plan['id']}';
    await widget.repository.generateDueEntries(planId: planId);
    return widget.repository.entries(planId);
  }

  void reload() => setState(() {
    records = _loadRecords();
  });

  Future<void> run(Future<dynamic> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      if (mounted) reload();
    } catch (e) {
      if (mounted)
        setState(() => error = '$e'.replaceFirst('FormatException: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> editDate({Map<String, dynamic>? entry}) async {
    final date = TextEditingController(
      text: '${entry?['scheduledDate'] ?? widget.plan['startDate']}',
    );
    final note = TextEditingController(text: '${entry?['note'] ?? ''}');
    final values = await showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(entry != null ? '修改记录' : '补录定投记录'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: date,
                decoration: const InputDecoration(
                  labelText: '执行日期（YYYY-MM-DD）',
                ),
              ),
              if (entry != null)
                TextField(
                  controller: note,
                  maxLength: 200,
                  decoration: const InputDecoration(labelText: '备注'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, [date.text.trim(), note.text.trim()]),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    // Route transitions can still render the fields after the dialog resolves.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    date.dispose();
    note.dispose();
    if (values == null || !mounted) return;
    await run(
      () => entry != null
          ? widget.repository.updateEntry(
              '${entry['id']}',
              values[0],
              values[1],
            )
          : widget.repository.generateEntry(
              '${widget.plan['id']}',
              values[0],
              supplement: true,
            ),
    );
  }

  Future<void> deleteEntry(Map<String, dynamic> entry) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除本期记录？'),
        content: Text('删除 ${entry['scheduledDate']} 的定投记录后，它不会再显示在本页。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      await run(() => widget.repository.deleteEntry('${entry['id']}'));
    }
  }

  Future<void> confirm(Map<String, dynamic> entry) async {
    final action = entry['type'] == 'sell' ? '卖出' : '买入';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认本期已${action == '卖出' ? '执行' : '扣款'}？'),
        content: Text(
          '仅在销售平台已${action == '卖出' ? '执行' : '扣款'}后确认。将生成一笔$action交易，正式净值缺失时保持待确认，不计入正式持仓。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('确认已${action == 'sell' ? '执行' : '扣款'}'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted)
      await run(() => widget.repository.confirmEntry('${entry['id']}'));
  }

  Widget _planHeader(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = widget.plan['enabled'] == true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.plan['fundName']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${widget.plan['fundCode']} · ${enabled ? '定投中' : '已暂停'}',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: busy ? null : () => editDate(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('补录'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _entryCard(BuildContext context, Map<String, dynamic> item) {
    final colors = Theme.of(context).colorScheme;
    final isSell = item['type'] == 'sell';
    final isPending = item['status'] == 'pending';
    final note = '${item['note'] ?? ''}'.trim();
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '${item['scheduledDate']} · ${isSell ? '卖出' : '买入'}',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _entryStatus(item['status']),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 18,
              runSpacing: 5,
              children: [
                Text(
                  item['mode'] == 'shares'
                      ? '${item['shares']} 份'
                      : '金额 ${item['amount']}',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                Text(
                  '手续费 ${item['feeMode'] == 'fixed' ? '${item['fixedFee'] ?? 0} 元' : '${item['feeRate'] ?? 0}%'}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              '来源：定投计划',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text('备注：$note'),
            ],
            if (item['transactionId'] != null) ...[
              const SizedBox(height: 5),
              Text('关联交易：${item['transactionId']}'),
            ],
            if (item['pendingReason'] != null) ...[
              const SizedBox(height: 5),
              Text('${item['pendingReason']}'),
            ],
            if (isPending) ...[
              const SizedBox(height: 10),
              Divider(height: 1, color: colors.outlineVariant),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: busy ? null : () => confirm(item),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 8,
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(isSell ? '确认已执行' : '确认扣款'),
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: busy ? null : () => editDate(entry: item),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 8,
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('修改'),
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: busy ? null : () => deleteEntry(item),
                      style: TextButton.styleFrom(
                        foregroundColor: colors.error,
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 8,
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('删除'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('定投一期记录')),
    body: ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _planHeader(context),
        if (error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: records,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextButton(
                  onPressed: reload,
                  child: const Text('记录读取失败，点击重试'),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: LinearProgressIndicator(),
              );
            }
            final items = [...snapshot.data!]
              ..sort(
                (a, b) =>
                    '${b['scheduledDate']}'.compareTo('${a['scheduledDate']}'),
              );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 20, 16, 0),
                    child: Text('暂无定投记录'),
                  ),
                for (final item in items) _entryCard(context, item),
              ],
            );
          },
        ),
      ],
    ),
  );
}

String _entryStatus(dynamic status) => switch (status) {
  'pending' => '待记账',
  'pending-confirmation' => '交易待净值确认',
  'confirmed' => '已确认',
  'skipped' => '已跳过',
  _ => '$status',
};

String _cycleLabel(String cycle) => switch (cycle) {
  'daily' => '每天',
  'weekly' => '每周',
  'monthly' => '每月',
  _ => cycle,
};

String _today() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}
