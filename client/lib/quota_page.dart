import 'package:flutter/material.dart';
import 'data/quota_repository.dart';

class QuotaPage extends StatefulWidget {
  const QuotaPage({required this.repository, super.key});
  final QuotaRepository repository;
  @override
  State<QuotaPage> createState() => _QuotaPageState();
}

class _QuotaPageState extends State<QuotaPage> {
  List<Quota> items = [];
  bool loading = true, busy = false, ascending = false;
  String? error;
  String category = '全部', query = '', sort = 'limit';
  @override
  void initState() { super.initState(); load(); }
  @override
  void didUpdateWidget(QuotaPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) { items = []; load(); }
  }
  Future<void> load() async {
    try {
      final rows = await widget.repository.list();
      if (mounted) setState(() { items = rows; loading = false; });
    } catch (e) { if (mounted) setState(() { error = '$e'; loading = false; }); }
  }
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try { await action(); }
    catch (e) { if (mounted) setState(() => error = '$e'); }
    finally { await load(); if (mounted) setState(() => busy = false); }
  }
  Future<void> edit(Quota q) async {
    final limit = TextEditingController(text: '${q['limit'] ?? ''}');
    var status = quotaStatus('${q['status']}');
    var changeStatus = false, changeLimit = false;
    final fields = await showDialog<Quota>(context: context, builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: Text('修改 ${q['code']}'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          CheckboxListTile(title: const Text('覆盖申购状态'), value: changeStatus, onChanged: (v) => update(() => changeStatus = v!)),
          DropdownButtonFormField<String>(initialValue: status, items: [
            for (final s in ['开放申购', '暂停申购', '限大额', '未知']) DropdownMenuItem(value: s, child: Text(s)),
          ], onChanged: (v) => update(() => status = v!)),
          CheckboxListTile(title: const Text('覆盖单日限额'), value: changeLimit, onChanged: (v) => update(() => changeLimit = v!)),
          TextField(controller: limit, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '单日限额（元，留空表示未披露）')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: !changeStatus && !changeLimit ? null : () {
            try {
              Navigator.pop(context, <String, dynamic>{if (changeStatus) 'status': status, if (changeLimit) 'limit': quotaAmount(limit.text)});
            } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
          }, child: const Text('保存')),
        ],
      )));
    if (fields != null && mounted) await run(() => widget.repository.setOverride('${q['code']}', fields));
  }
  Future<void> detail(Quota q) async {
    await showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: Text('${q['name']}（${q['code']}）'),
      content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('分类：${q['category'] ?? 'QDII'}'),
        Text('状态：${q['status']} · 单日限额：${amount(q['limit'])}'),
        Text('近一年收益率：${q['annualReturn'] == null ? '未披露' : '${(num.parse('${q['annualReturn']}') * 100).toStringAsFixed(2)}%'}'),
        Text('来源：${q['source'] ?? '未披露'} · ${q['sourceType'] ?? '未披露'}'),
        SelectableText('来源链接：${q['sourceUrl'] ?? '未披露'}'),
        Text('更新时间：${q['updatedAt'] ?? '未披露'}'),
        Text('优先级：${q['valueSource'] == 'user' ? '手动覆盖' : '自动采集'}'),
        Text('覆盖字段：${q['overrideFields'] ?? []}'),
        Text('自动状态：${q['automaticStatus'] ?? q['status'] ?? '未知'}'),
        Text('自动限额：${amount(q['automaticLimit'] ?? (q['valueSource'] != 'user' ? q['limit'] : null))}'),
        Text('说明：${q['detail'] ?? '未披露'}'),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
    ));
  }
  String amount(dynamic value) => value == null ? '未披露' : '¥${quotaAmount(value)!.toStringAsFixed(2)}';
  @override
  Widget build(BuildContext context) {
    final filtered = items.where((q) => (category == '全部' || q['category'] == category) &&
      '${q['name']} ${q['code']}'.toLowerCase().contains(query.toLowerCase())).toList();
    filtered.sort((a, b) {
      if (sort == 'limit') {
        int group(Quota q) => q['status'] == '暂停申购' ? 2 : q['limit'] == null ? 1 : 0;
        final g = group(a).compareTo(group(b));
        if (g != 0) return g;
        return (quotaAmount(a['limit']) ?? 0).compareTo(quotaAmount(b['limit']) ?? 0) * (ascending ? 1 : -1);
      }
      return '${a[sort]}'.compareTo('${b[sort]}') * (ascending ? 1 : -1);
    });
    final dates = items.map((q) => DateTime.tryParse('${q['updatedAt']}')).whereType<DateTime>().toList()..sort();
    final latest = dates.isEmpty ? null : dates.last;
    final stale = latest == null || DateTime.now().toUtc().difference(latest) > const Duration(hours: 24);
    return ListView(padding: const EdgeInsets.all(16), children: [
      for (final c in ['纳斯达克100', '标普500']) Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(
        '$c · ${items.where((q) => q['category'] == c).length} 只\n暂停申购 ${items.where((q) => q['category'] == c && q['status'] == '暂停申购').length} · 限大额 ${items.where((q) => q['category'] == c && q['status'] == '限大额').length}'))),
      Text('最近更新：${latest?.toLocal().toString() ?? '尚未刷新'}${stale ? ' · 需要刷新' : ''}'),
      FilledButton.icon(onPressed: busy ? null : () => run(() async { await widget.repository.refresh(); }),
        icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
        label: const Text('刷新额度')),
      if (error != null) TextButton(onPressed: busy ? null : () => run(() async { await widget.repository.refresh(); }), child: Text('$error · 点击重试')),
      Wrap(spacing: 8, children: [for (final c in ['全部', '纳斯达克100', '标普500'])
        ChoiceChip(label: Text(c), selected: category == c, onSelected: (_) => setState(() => category = c))]),
      TextField(decoration: const InputDecoration(labelText: '搜索基金名称或代码', prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => query = v)),
      Row(children: [
        Expanded(child: DropdownButton<String>(isExpanded: true, value: sort, items: [
          for (final pair in [('category', '分类'), ('name', '基金名称'), ('status', '状态'), ('limit', '单日限额')])
            DropdownMenuItem(value: pair.$1, child: Text('按${pair.$2}排序')),
        ], onChanged: (v) => setState(() => sort = v!))),
        IconButton(tooltip: ascending ? '升序' : '降序', onPressed: () => setState(() => ascending = !ascending), icon: Icon(ascending ? Icons.arrow_upward : Icons.arrow_downward)),
      ]),
      if (loading) const Center(child: CircularProgressIndicator()),
      if (!loading && filtered.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('暂无匹配额度；可联网刷新获取数据')),
      for (final q in filtered) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ListTile(contentPadding: EdgeInsets.zero, onTap: () => detail(q), title: Text('${q['name']} · ${q['code']}'),
          subtitle: Text('${q['status']} · 单日限额 ${amount(q['limit'])}\n${q['valueSource'] == 'user' ? '手动覆盖' : '自动采集'} · ${q['source'] ?? '来源未披露'}\n${q['updatedAt'] ?? '更新时间未披露'}')),
        Wrap(children: [
          TextButton(onPressed: () => detail(q), child: const Text('详情')),
          TextButton(onPressed: busy ? null : () => edit(q), child: const Text('修改')),
          if (q['valueSource'] == 'user') TextButton(onPressed: busy ? null : () => run(() => widget.repository.restore('${q['code']}')), child: const Text('恢复自动')),
        ]),
      ]))),
    ]);
  }
}
