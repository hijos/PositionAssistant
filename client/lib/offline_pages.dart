import 'package:flutter/material.dart';

import 'data/offline_repository.dart';
import 'data/repository.dart';

class LocalPlansPage extends StatefulWidget {
  const LocalPlansPage({required this.open, super.key});
  final Future<Repository> Function() open;
  @override
  State<LocalPlansPage> createState() => _LocalPlansPageState();
}

class _LocalPlansPageState extends State<LocalPlansPage> {
  late final LocalPlanRepository repository = LocalPlanRepository(widget.open);
  late Future<List<Map<String, dynamic>>> plans = repository.list();
  void reload() => setState(() { plans = repository.list(); });

  Future<void> createPlan() async {
    final code = TextEditingController(text: '000001');
    final name = TextEditingController(text: '本地基金');
    final value = TextEditingController(text: '100');
    final date = TextEditingController(text: _today());
    var cycle = 'monthly';
    var day = 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('新建定投计划'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: code, decoration: const InputDecoration(labelText: '基金代码')),
              TextField(controller: name, decoration: const InputDecoration(labelText: '基金名称')),
              TextField(controller: value, decoration: const InputDecoration(labelText: '金额或份额'), keyboardType: TextInputType.number),
              TextField(controller: date, decoration: const InputDecoration(labelText: '起始日期')),
              DropdownButtonFormField<String>(initialValue: cycle, items: const [
                DropdownMenuItem(value: 'weekly', child: Text('每周')),
                DropdownMenuItem(value: 'monthly', child: Text('每月')),
              ], onChanged: (v) => setDialogState(() { cycle = v ?? cycle; if (cycle == 'weekly' && day > 7) day = 1; })),
              DropdownButtonFormField<int>(key: ValueKey(cycle), initialValue: day, items: [
                for (var i = 1; i <= (cycle == 'weekly' ? 7 : 31); i++) DropdownMenuItem(value: i, child: Text('执行日 $i')),
              ], onChanged: (v) => setDialogState(() => day = v ?? day)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('保存')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await repository.create(
        fundCode: code.text.trim(), fundName: name.text.trim(), mode: 'amount',
        value: double.parse(value.text), cycle: cycle, startDate: date.text.trim(), executionDay: day,
      );
      reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('定投计划')),
    floatingActionButton: FloatingActionButton(onPressed: createPlan, child: const Icon(Icons.add)),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: plans,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: TextButton(onPressed: reload, child: const Text('定投读取失败，点击重试')));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final items = snapshot.data!;
        if (items.isEmpty) return const Center(child: Text('暂无定投计划'));
        return ListView(padding: const EdgeInsets.all(16), children: [
          for (final plan in items) Card(child: ListTile(
            onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => LocalPlanEntriesPage(repository: repository, plan: plan))),
            title: Text('${plan['fundName']} · ${plan['fundCode']}'),
            subtitle: Text('${plan['cycle']} · 执行日 ${plan['executionDay']} · ${plan['enabled'] == true ? '启用' : '暂停'}'),
            trailing: Switch(value: plan['enabled'] == true, onChanged: (v) async { await repository.setEnabled('${plan['id']}', v); reload(); }),
          )),
        ]);
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
  late final LocalQuotaRepository repository = LocalQuotaRepository(widget.open);
  late Future<List<Map<String, dynamic>>> quotas = repository.list();
  void reload() => setState(() { quotas = repository.list(); });
  Future<void> edit() async {
    final code = TextEditingController(text: '000001');
    final name = TextEditingController(text: '本地基金');
    final status = TextEditingController(text: '开放');
    final limit = TextEditingController(text: '1000');
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('添加或修改额度'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: code, decoration: const InputDecoration(labelText: '基金代码')),
        TextField(controller: name, decoration: const InputDecoration(labelText: '基金名称')),
        TextField(controller: status, decoration: const InputDecoration(labelText: '申购状态')),
        TextField(controller: limit, decoration: const InputDecoration(labelText: '单日限额')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('保存'))],
    ));
    if (ok != true || !mounted) return;
    try { await repository.save(code: code.text.trim(), name: name.text.trim(), category: 'QDII', status: status.text, limit: limit.text); reload(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('额度列表')),
    floatingActionButton: FloatingActionButton(onPressed: edit, child: const Icon(Icons.edit)),
    body: FutureBuilder<List<Map<String, dynamic>>>(future: quotas, builder: (context, snapshot) {
      if (snapshot.hasError) return Center(child: TextButton(onPressed: reload, child: const Text('额度读取失败，点击重试')));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final items = snapshot.data!;
      if (items.isEmpty) return const Center(child: Text('暂无额度数据'));
      return ListView(padding: const EdgeInsets.all(16), children: [for (final item in items) Card(child: ListTile(
        title: Text('${item['name']} · ${item['code']}'), subtitle: Text('${item['status']} · 单日限额 ${item['limit']}'),
        trailing: IconButton(icon: const Icon(Icons.restore), onPressed: () async { await repository.restore('${item['code']}'); reload(); }),
      ))]);
    }),
  );
}

class LocalPlanEntriesPage extends StatefulWidget {
  const LocalPlanEntriesPage({required this.repository, required this.plan, super.key});
  final LocalPlanRepository repository;
  final Map<String, dynamic> plan;
  @override
  State<LocalPlanEntriesPage> createState() => _LocalPlanEntriesPageState();
}

class _LocalPlanEntriesPageState extends State<LocalPlanEntriesPage> {
  late Future<List<Map<String, dynamic>>> records = widget.repository.entries('${widget.plan['id']}');
  bool busy = false;
  String? error;
  void reload() => setState(() { records = widget.repository.entries('${widget.plan['id']}'); });

  Future<void> run(Future<dynamic> Function() action) async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try {
      await action();
      if (mounted) reload();
    } catch (e) {
      if (mounted) setState(() => error = '$e'.replaceFirst('FormatException: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> editDate({Map<String, dynamic>? entry, bool supplement = false}) async {
    final date = TextEditingController(text: '${entry?['scheduledDate'] ?? widget.plan['startDate']}');
    final note = TextEditingController(text: '${entry?['note'] ?? ''}');
    final values = await showDialog<List<String>>(context: context, builder: (context) => AlertDialog(
      title: Text(entry != null ? '修改一期' : supplement ? '补录一期' : '生成一期'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: date, decoration: const InputDecoration(labelText: '执行日期（YYYY-MM-DD）')),
        if (entry != null) TextField(controller: note, maxLength: 200, decoration: const InputDecoration(labelText: '备注')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, [date.text.trim(), note.text.trim()]), child: const Text('保存')),
      ],
    ));
    // Route transitions can still render the fields after the dialog resolves.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    date.dispose(); note.dispose();
    if (values == null || !mounted) return;
    await run(() => entry != null
        ? widget.repository.updateEntry('${entry['id']}', values[0], values[1])
        : widget.repository.generateEntry('${widget.plan['id']}', values[0], supplement: supplement));
  }

  Future<void> confirm(Map<String, dynamic> entry) async {
    final accepted = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('确认本期已扣款？'),
      content: const Text('仅在销售平台已扣款后确认。将生成一笔买入交易，正式净值缺失时保持待确认，不计入正式持仓。'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('确认已扣款'))],
    ));
    if (accepted == true && mounted) await run(() => widget.repository.confirmEntry('${entry['id']}'));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('定投一期记录')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Text('${widget.plan['fundName']} · ${widget.plan['fundCode']}'),
      Wrap(spacing: 8, children: [
        FilledButton(onPressed: busy || widget.plan['enabled'] != true ? null : () => editDate(), child: const Text('生成一期')),
        OutlinedButton(onPressed: busy ? null : () => editDate(supplement: true), child: const Text('补录一期')),
      ]),
      if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      FutureBuilder<List<Map<String, dynamic>>>(future: records, builder: (context, snapshot) {
        if (snapshot.hasError) return TextButton(onPressed: reload, child: const Text('记录读取失败，点击重试'));
        if (!snapshot.hasData) return const LinearProgressIndicator();
        final items = [...snapshot.data!]..sort((a, b) => '${b['scheduledDate']}'.compareTo('${a['scheduledDate']}'));
        return Column(children: [
          if (items.isEmpty) const Text('暂无定投记录'),
          for (final item in items) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${item['scheduledDate']} · ${_entryStatus(item['status'])}'),
              Text(item['mode'] == 'shares' ? '${item['shares']} 份' : '金额 ${item['amount']}'),
              if (item['note'] != null) Text('${item['note']}'),
              if (item['transactionId'] != null) Text('关联交易：${item['transactionId']}'),
              if (item['pendingReason'] != null) Text('${item['pendingReason']}'),
              if (item['status'] == 'pending') Wrap(spacing: 8, children: [
                TextButton(onPressed: busy ? null : () => confirm(item), child: const Text('确认扣款')),
                TextButton(onPressed: busy ? null : () => editDate(entry: item), child: const Text('修改')),
                TextButton(onPressed: busy ? null : () => run(() => widget.repository.skipEntry('${item['id']}')), child: const Text('跳过')),
              ]),
            ],
          ))),
        ]);
      }),
    ]),
  );
}

String _entryStatus(dynamic status) => switch (status) {
  'pending' => '待记账', 'pending-confirmation' => '交易待净值确认',
  'confirmed' => '已确认', 'skipped' => '已跳过', _ => '$status',
};

String _today() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}
