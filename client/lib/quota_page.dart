import 'package:flutter/material.dart';
import 'data/quota_repository.dart';

class QuotaPage extends StatefulWidget {
  const QuotaPage({required this.repository, this.refreshToken = 0, super.key});
  final QuotaRepository repository;
  /// 每次点击底部「额度」tab 时递增，触发一次自动刷新。
  final int refreshToken;
  @override State<QuotaPage> createState() => _QuotaPageState();
}

class _QuotaPageState extends State<QuotaPage> {
  List<Quota> items = [];
  bool loading = true, busy = false, ascending = false;
  String? error;
  String category = '全部', query = '', sort = 'directLimit';

  static const categories = ['全部', '纳斯达克100', '标普500'];
  static const sortOptions = [
    ('preferred', '按推荐渠道'),
    ('directLimit', '按直销额度'),
    ('distributionLimit', '按代销额度'),
    ('name', '按基金名称'),
  ];

  @override
  void initState() {
    super.initState();
    load();
    if (widget.refreshToken > 0) _autoRefresh();
  }

  @override
  void didUpdateWidget(QuotaPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      items = [];
      load();
    }
    if (widget.refreshToken != oldWidget.refreshToken) _autoRefresh();
  }

  Future<void> load() async {
    try {
      final rows = await widget.repository.list();
      if (mounted) setState(() { items = rows; loading = false; error = null; });
    } catch (e) {
      if (mounted) setState(() { error = '${e}'; loading = false; });
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = '${e}');
    } finally {
      await load();
      if (mounted) setState(() => busy = false);
    }
  }

  void _autoRefresh() => run(() async { await widget.repository.refresh(); });

  QuotaChannel channel(Quota q, String name) {
    final raw = q['channels'];
    final value = raw is Map ? raw[name] : null;
    return normalizeQuotaChannel(value is Map ? Map<String, dynamic>.from(value) : null, q);
  }

  bool hasChannel(Quota q, String name) => q['channels'] is Map && (q['channels'] as Map).containsKey(name);

  String _statusText(QuotaChannel c, {required bool channelKnown}) {
    if (!channelKnown) return '未披露';
    final status = '${c['status']}';
    return status == '未知' ? '未披露' : status;
  }

  String _limitText(QuotaChannel c, {required bool channelKnown}) {
    if (!channelKnown) return '-';
    final limit = quotaAmount(c['limit']);
    if (limit == null) return '未披露';
    if (limit >= 100000000) return '${(limit / 100000000).toStringAsFixed(limit % 100000000 == 0 ? 0 : 2)}亿';
    if (limit >= 10000) return '${(limit / 10000).toStringAsFixed(limit % 10000 == 0 ? 0 : 2)}万';
    return limit.toStringAsFixed(0);
  }

  String _annualReturnText(Quota q) {
    final raw = q['annualReturn'];
    if (raw == null) return '-';
    final value = num.tryParse('${raw}');
    if (value == null) return '-';
    return '${value >= 0 ? '+' : ''}${(value * 100).toStringAsFixed(2)}%';
  }

  String _feeRateText(Quota q) {
    final raw = q['feeRate'];
    if (raw == null) return '-';
    final value = num.tryParse('${raw}');
    if (value == null) return '-';
    return '${value.toStringAsFixed(2)}%';
  }

  Color _statusColor(BuildContext context, QuotaChannel c, {required bool channelKnown}) {
    final scheme = Theme.of(context).colorScheme;
    if (!channelKnown) return scheme.onSurfaceVariant;
    switch ('${c['status']}') {
      case '开放申购': return scheme.primary;
      case '限大额': return const Color(0xffb26a00);
      case '暂停申购': return scheme.error;
      default: return scheme.onSurfaceVariant;
    }
  }

  Future<void> edit(Quota q) async {
    String selected = 'direct';
    final status = TextEditingController(text: '${channel(q, selected)['status'] ?? '未知'}');
    final limit = TextEditingController(text: '${channel(q, selected)['limit'] ?? ''}');
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
    final direct = hasChannel(q, 'direct');
    String lineOf(String key) {
      final c = channel(q, key);
      return '${c['status']} · ${quotaAmount(c['limit']) == null ? '未披露' : '¥${quotaAmount(c['limit'])!.toStringAsFixed(2)}'}';
    }
    await showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: Text('${q['name']}（${q['code']}）'),
      content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('分类：${q['category'] ?? 'QDII'}'), Text('代销：${lineOf('distribution')}'), Text('直销：${direct ? lineOf('direct') : '暂无公开数据'}'),
        Text('推荐渠道：${q['preferredChannel'] == 'direct' ? '直销' : q['preferredChannel'] == 'distribution' ? '代销' : '暂无'}'), Text('数据质量：${q['dataQuality'] ?? 'unknown'}'),
        Text('代销来源：${channel(q, 'distribution')['source'] ?? '未披露'}'), Text('直销来源：${direct ? channel(q, 'direct')['source'] ?? '未披露' : '未披露'}'),
        Text('近一年收益率：${q['annualReturn'] == null ? '未披露' : '${(num.parse('${q['annualReturn']}') * 100).toStringAsFixed(2)}%'}'), Text('说明：${q['detail'] ?? '未披露'}'),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
    ));
  }

  dynamic sortValue(Quota q) {
    if (sort == 'directLimit') return quotaAmount(channel(q, 'direct')['limit']) ?? -1;
    if (sort == 'distributionLimit') return quotaAmount(channel(q, 'distribution')['limit']) ?? -1;
    if (sort == 'preferred') return '${q['preferredChannel']}';
    return '${q[sort]}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final filtered = items.where((q) => (category == '全部' || q['category'] == category) && '${q['name']} ${q['code']}'.toLowerCase().contains(query.toLowerCase())).toList();
    filtered.sort((a, b) { final av = sortValue(a), bv = sortValue(b); final result = av is num && bv is num ? av.compareTo(bv) : '${av}'.compareTo('${bv}'); return ascending ? result : -result; });

    return Stack(children: [
      ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
        _buildCategoryChips(),
        const SizedBox(height: 12),
        _buildToolbar(theme, scheme),
        if (error != null) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextButton(onPressed: busy ? null : _autoRefresh, child: Text('${error} · 点击重试')),
        ),
        const SizedBox(height: 12),
        if (loading) const Padding(padding: EdgeInsets.symmetric(vertical: 48), child: Center(child: CircularProgressIndicator())),
        if (!loading && filtered.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('暂无匹配额度；切换到额度页时会自动联网刷新'))),
        for (final q in filtered) Padding(padding: const EdgeInsets.only(bottom: 10), child: _buildQuotaCard(theme, scheme, q)),
      ]),
      if (busy && !loading) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 2)),
    ]);
  }

  Widget _buildCategoryChips() {
    final scheme = Theme.of(context).colorScheme;
    int countOf(String c) => items.where((q) => q['category'] == c).length;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final c in categories) Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(c == '全部' ? c : '${c} · ${countOf(c)}只'),
            selected: category == c,
            showCheckmark: false,
            selectedColor: scheme.primaryContainer,
            labelStyle: TextStyle(
              color: category == c ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
              fontWeight: category == c ? FontWeight.w600 : FontWeight.normal,
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: category == c ? Colors.transparent : scheme.outlineVariant)),
            onSelected: (_) => setState(() => category = c),
          ),
        ),
      ]),
    );
  }

  Widget _buildToolbar(ThemeData theme, ColorScheme scheme) {
    return Row(children: [
      Expanded(
        child: TextField(
          decoration: InputDecoration(
            hintText: '搜索基金名称或代码',
            prefixIcon: const Icon(Icons.search, size: 20),
            isDense: true,
            filled: true,
            fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
          onChanged: (value) => setState(() => query = value),
        ),
      ),
      const SizedBox(width: 8),
      PopupMenuButton<String>(
        tooltip: '排序方式',
        initialValue: sort,
        onSelected: (value) => setState(() => sort = value),
        itemBuilder: (context) => [for (final option in sortOptions) PopupMenuItem(value: option.$1, child: Text(option.$2))],
        child: _toolbarPill(scheme, Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.sort, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(sortOptions.firstWhere((o) => o.$1 == sort).$2, style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
          Icon(Icons.arrow_drop_down, size: 16, color: scheme.onSurfaceVariant),
        ])),
      ),
      const SizedBox(width: 8),
      Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() => ascending = !ascending),
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Icon(ascending ? Icons.arrow_upward : Icons.arrow_downward, size: 18, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    ]);
  }

  Widget _toolbarPill(ColorScheme scheme, Widget child) => Container(
    decoration: BoxDecoration(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(20),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    child: child,
  );

  Widget _buildQuotaCard(ThemeData theme, ColorScheme scheme, Quota q) {
    final distKnown = hasChannel(q, 'distribution');
    final directKnown = hasChannel(q, 'direct');
    final dist = channel(q, 'distribution');
    final direct = channel(q, 'direct');
    final annual = q['annualReturn'] == null ? null : num.tryParse('${q['annualReturn']}');
    final userOverride = q['valueSource'] == 'user';

    return Card(
      elevation: 0,
      color: scheme.surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => detail(q),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${q['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Row(children: [
                    Text('${q['code']}', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    const SizedBox(width: 8),
                    Text('近一年 ${_annualReturnText(q)}', style: theme.textTheme.bodySmall?.copyWith(color: annual == null ? scheme.onSurfaceVariant : _returnColor(annual), fontWeight: annual == null ? FontWeight.normal : FontWeight.w600)),
                    if (userOverride) ...[
                      const SizedBox(width: 8),
                      _badge(scheme, '手动'),
                    ],
                  ]),
                ]),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                _channelLine(theme, scheme, '代销', dist, known: distKnown),
                const SizedBox(height: 2),
                _channelLine(theme, scheme, '直销', direct, known: directKnown),
                const SizedBox(height: 4),
                Text('费率 ${_feeRateText(q)}', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ]),
            ]),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              _cardAction(theme, scheme, '详情', () => detail(q)),
              _cardAction(theme, scheme, '修改', busy ? null : () => edit(q)),
              if (userOverride) _cardAction(theme, scheme, '恢复自动', busy ? null : () => run(() => widget.repository.restore('${q['code']}'))),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _channelLine(ThemeData theme, ColorScheme scheme, String label, QuotaChannel c, {required bool known}) {
    final color = _statusColor(context, c, channelKnown: known);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('${label} ', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      Text(_statusText(c, channelKnown: known), style: theme.textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w600)),
      Text(' ${_limitText(c, channelKnown: known)}', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
    ]);
  }

  Widget _badge(ColorScheme scheme, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(4)),
    child: Text(text, style: TextStyle(fontSize: 10, color: scheme.onSecondaryContainer, fontWeight: FontWeight.w600)),
  );

  Widget _cardAction(ThemeData theme, ColorScheme scheme, String label, VoidCallback? onPressed) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), tapTargetSize: MaterialTapTargetSize.shrinkWrap, foregroundColor: scheme.primary),
    child: Text(label, style: theme.textTheme.labelMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600)),
  );

  Color _returnColor(num value) => value >= 0 ? const Color(0xffc62828) : const Color(0xff2e7d32);
}
