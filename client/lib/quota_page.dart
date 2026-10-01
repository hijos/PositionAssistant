import 'package:flutter/material.dart';
import 'data/quota_repository.dart';

class QuotaPage extends StatefulWidget {
  const QuotaPage({required this.repository, super.key});
  final QuotaRepository repository;
  @override State<QuotaPage> createState() => _QuotaPageState();
}

class _QuotaPageState extends State<QuotaPage> {
  List<Quota> items = []; bool loading = true, busy = false, ascending = false;
  String? error; String category = '全部', query = '', sort = 'directLimit';
  @override void initState() { super.initState(); load(); }
  @override void didUpdateWidget(QuotaPage oldWidget) { super.didUpdateWidget(oldWidget); if (oldWidget.repository != widget.repository) { items = []; load(); } }
  Future<void> load() async { try { final rows = await widget.repository.list(); if (mounted) setState(() { items = rows; loading = false; error = null; }); } catch (e) { if (mounted) setState(() { error = '$e'; loading = false; }); } }
  Future<void> run(Future<void> Function() action) async { if (busy) return; setState(() { busy = true; error = null; }); try { await action(); } catch (e) { if (mounted) setState(() => error = '$e'); } finally { await load(); if (mounted) setState(() => busy = false); } }
  QuotaChannel channel(Quota q, String name) { final raw = q['channels']; final value = raw is Map ? raw[name] : null; return normalizeQuotaChannel(value is Map ? Map<String, dynamic>.from(value) : null, q); }
  String amount(dynamic value) => value == null ? '未披露' : '¥${quotaAmount(value)!.toStringAsFixed(2)}';
  String line(Quota q, String key) { final c = channel(q, key); return '${c['status']} · ${amount(c['limit'])}'; }
  Future<void> edit(Quota q) async {
    String selected = 'direct'; final status = TextEditingController(text: '${channel(q, selected)['status'] ?? '未知'}'); final limit = TextEditingController(text: '${channel(q, selected)['limit'] ?? ''}');
    final fields = await showDialog<Quota>(context: context, builder: (context) => StatefulBuilder(builder: (context, update) => AlertDialog(
      title: Text('修改 ${q['code']}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(initialValue: selected, items: const [DropdownMenuItem(value: 'distribution', child: Text('代销渠道')), DropdownMenuItem(value: 'direct', child: Text('直销渠道'))], onChanged: (value) { if (value == null) return; update(() { selected = value; status.text = '${channel(q, selected)['status'] ?? '未知'}'; limit.text = '${channel(q, selected)['limit'] ?? ''}'; }); }),
        TextField(controller: status, decoration: const InputDecoration(labelText: '申购状态')),
        TextField(controller: limit, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '单日限额（元，留空表示未披露）')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, {'channel': selected, 'status': quotaStatus(status.text), 'limit': quotaAmount(limit.text)}), child: const Text('保存'))],
    )));
    if (fields != null && mounted) await run(() => widget.repository.setOverride('${q['code']}', fields));
  }
  Future<void> detail(Quota q) async {
    final direct = q['channels'] is Map && (q['channels'] as Map).containsKey('direct');
    await showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: Text('${q['name']}（${q['code']}）'),
      content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('分类：${q['category'] ?? 'QDII'}'), Text('代销：${line(q, 'distribution')}'), Text('直销：${direct ? line(q, 'direct') : '暂无公开数据'}'),
        Text('推荐渠道：${q['preferredChannel'] == 'direct' ? '直销' : q['preferredChannel'] == 'distribution' ? '代销' : '暂无'}'), Text('数据质量：${q['dataQuality'] ?? 'unknown'}'),
        Text('代销来源：${channel(q, 'distribution')['source'] ?? '未披露'}'), Text('直销来源：${direct ? channel(q, 'direct')['source'] ?? '未披露' : '未披露'}'),
        Text('近一年收益率：${q['annualReturn'] == null ? '未披露' : '${(num.parse('${q['annualReturn']}') * 100).toStringAsFixed(2)}%'}'), Text('说明：${q['detail'] ?? '未披露'}'),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
    ));
  }
  dynamic sortValue(Quota q) { if (sort == 'directLimit') return quotaAmount(channel(q, 'direct')['limit']) ?? -1; if (sort == 'distributionLimit') return quotaAmount(channel(q, 'distribution')['limit']) ?? -1; if (sort == 'preferred') return '${q['preferredChannel']}'; return '${q[sort]}'; }
  @override Widget build(BuildContext context) {
    final filtered = items.where((q) => (category == '全部' || q['category'] == category) && '${q['name']} ${q['code']}'.toLowerCase().contains(query.toLowerCase())).toList();
    filtered.sort((a, b) { final av = sortValue(a), bv = sortValue(b); final result = av is num && bv is num ? av.compareTo(bv) : '$av'.compareTo('$bv'); return ascending ? result : -result; });
    final dates = items.map((q) => DateTime.tryParse('${q['updatedAt']}')).whereType<DateTime>().toList()..sort(); final latest = dates.isEmpty ? null : dates.last;
    return ListView(padding: const EdgeInsets.all(16), children: [
      for (final c in ['纳斯达克100', '标普500']) Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('$c · ${items.where((q) => q['category'] == c).length} 只'))),
      Text('最近更新：${latest?.toLocal().toString() ?? '尚未刷新'}'),
      FilledButton.icon(onPressed: busy ? null : () => run(() async { await widget.repository.refresh(); }), icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh), label: const Text('刷新额度')),
      if (error != null) TextButton(onPressed: busy ? null : () => run(() async { await widget.repository.refresh(); }), child: Text('$error · 点击重试')),
      Wrap(spacing: 8, children: [for (final c in ['全部', '纳斯达克100', '标普500']) ChoiceChip(label: Text(c), selected: category == c, onSelected: (_) => setState(() => category = c))]),
      TextField(decoration: const InputDecoration(labelText: '搜索基金名称或代码', prefixIcon: Icon(Icons.search)), onChanged: (value) => setState(() => query = value)),
      Row(children: [Expanded(child: DropdownButton<String>(isExpanded: true, value: sort, items: const [DropdownMenuItem(value: 'preferred', child: Text('按推荐渠道排序')), DropdownMenuItem(value: 'directLimit', child: Text('按直销额度排序')), DropdownMenuItem(value: 'distributionLimit', child: Text('按代销额度排序')), DropdownMenuItem(value: 'name', child: Text('按基金名称排序'))], onChanged: (value) => setState(() => sort = value!))), IconButton(onPressed: () => setState(() => ascending = !ascending), icon: Icon(ascending ? Icons.arrow_upward : Icons.arrow_downward))]),
      if (loading) const Center(child: CircularProgressIndicator()), if (!loading && filtered.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('暂无匹配额度；可联网刷新获取数据')),
      for (final q in filtered) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ListTile(contentPadding: EdgeInsets.zero, onTap: () => detail(q), title: Text('${q['name']} · ${q['code']}'), subtitle: Text('代销：${line(q, 'distribution')}\n直销：${q['channels'] is Map && (q['channels'] as Map).containsKey('direct') ? line(q, 'direct') : '暂无公开数据'}\n推荐渠道：${q['preferredChannel'] == 'direct' ? '直销' : q['preferredChannel'] == 'distribution' ? '代销' : '暂无'}')),
        Wrap(children: [TextButton(onPressed: () => detail(q), child: const Text('详情')), TextButton(onPressed: busy ? null : () => edit(q), child: const Text('修改')), if (q['valueSource'] == 'user') TextButton(onPressed: busy ? null : () => run(() => widget.repository.restore('${q['code']}')), child: const Text('恢复自动'))]),
      ]))),
    ]);
  }
}
