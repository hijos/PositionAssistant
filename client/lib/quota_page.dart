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
  bool loading = true, busy = false, ascending = false, excludeC = false;
  String? error;
  String category = '全部', query = '', sort = 'directLimit';

  static const categories = ['全部', '纳斯达克100', '标普500'];
  static const sortOptions = [
    ('directLimit', '按直销额度'),
    ('distributionLimit', '按代销额度'),
    ('maxLimit', '按最大额度'),
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

  void _autoRefresh() => run(() async {
    await widget.repository.refresh();
    if (!mounted || widget.repository is! CloudQuotaRepository) return;
    final notice = (widget.repository as CloudQuotaRepository).takeUpdateNotice();
    if (notice != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(notice)));
    }
  });

  QuotaChannel channel(Quota q, String name) {
    final raw = q['channels'];
    final value = raw is Map ? raw[name] : null;
    return normalizeQuotaChannel(value is Map ? Map<String, dynamic>.from(value) : null, q);
  }

  String _annualReturnText(Quota q) {
    final raw = q['annualReturn'];
    if (raw == null) return '-';
    final value = num.tryParse('${raw}');
    if (value == null) return '-';
    return '${value >= 0 ? '+' : ''}${(value * 100).toStringAsFixed(2)}%';
  }

  Future<void> edit(Quota q) async {
    String selected = 'direct';
    final status = TextEditingController(text: '${channel(q, selected)['status'] ?? '未知'}');
    final limit = TextEditingController(text: '${channel(q, selected)['limit'] ?? ''}');
    final result = await showDialog<Map<String, dynamic>>(context: context, builder: (context) => StatefulBuilder(builder: (context, update) => AlertDialog(
      title: Text('修改 ${q['code']}'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        DropdownButtonFormField<String>(initialValue: selected, items: const [DropdownMenuItem(value: 'distribution', child: Text('代销渠道')), DropdownMenuItem(value: 'direct', child: Text('直销渠道'))], onChanged: (value) { if (value == null) return; update(() { selected = value; status.text = '${channel(q, selected)['status'] ?? '未知'}'; limit.text = '${channel(q, selected)['limit'] ?? ''}'; }); }),
        TextField(controller: status, decoration: const InputDecoration(labelText: '申购状态')),
        TextField(controller: limit, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '单日限额（元，留空表示未披露）')),
        const SizedBox(height: 12),
        Text('当上传某特定额度的用户足够多时，会自动修正云端额度数据。', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]),
      actions: [
        OverflowBar(
          spacing: 8,
          overflowSpacing: 4,
          children: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            OutlinedButton(onPressed: () => Navigator.pop(context, {'upload': false, 'fields': {'channel': selected, 'status': quotaStatus(status.text), 'limit': quotaAmount(limit.text)}}), child: const Text('保存')),
            FilledButton(onPressed: () => Navigator.pop(context, {'upload': true, 'fields': {'channel': selected, 'status': quotaStatus(status.text), 'limit': quotaAmount(limit.text)}}), child: const Text('保存并上传')),
          ],
        ),
      ],
    )));
    status.dispose();
    limit.dispose();
    if (result == null || !mounted) return;
    final fields = Map<String, dynamic>.from(result['fields'] as Map);
    final shouldUpload = result['upload'] == true;
    if (busy) return;
    setState(() { busy = true; error = null; });
    String? message;
    try {
      await widget.repository.setOverride('${q['code']}', fields);
      if (!shouldUpload) {
        message = '已保存到本机';
      } else {
        final upload = await widget.repository.uploadCorrection('${q['code']}', {
          ...fields,
          'revision': q['revision'],
        });
        message = upload.applied
            ? '已保存，云端额度已根据用户共识更新'
            : upload.duplicate
                ? '已保存，这条纠错已经上传过'
                : '已保存并上传，等待更多用户确认';
      }
    } catch (e) {
      if (shouldUpload) {
        message = '已保存，但上传失败：$e';
      } else if (mounted) {
        setState(() => error = '$e');
      }
    } finally {
      await load();
      if (mounted) {
        setState(() => busy = false);
        if (message != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  dynamic sortValue(Quota q) {
    if (sort == 'directLimit') return quotaAmount(channel(q, 'direct')['limit']) ?? -1;
    if (sort == 'distributionLimit') return quotaAmount(channel(q, 'distribution')['limit']) ?? -1;
    if (sort == 'maxLimit') {
      final direct = quotaAmount(channel(q, 'direct')['limit']) ?? -1;
      final distribution = quotaAmount(channel(q, 'distribution')['limit']) ?? -1;
      return direct > distribution ? direct : distribution;
    }
    return '${q[sort]}';
  }

  /// Rank of a fund inside its family: lettered share classes first in
  /// alphabetical order (A, C, D, I ...), unlettered names last.
  int shareClassRank(Quota q) {
    final letter = quotaShareClass('${q['name']}');
    return letter == null ? 100 : letter.codeUnitAt(0) - 0x41;
  }

  /// Whether the channel line is bolded under the current sort. For
  /// 按最大额度 only the channel carrying the larger limit is highlighted
  /// (both when equal; none when neither discloses a limit).
  bool _highlightChannel(Quota q, String name) {
    if (sort == 'directLimit') return name == 'direct';
    if (sort == 'distributionLimit') return name == 'distribution';
    if (sort != 'maxLimit') return false;
    final value = quotaAmount(channel(q, name)['limit']);
    final other = quotaAmount(channel(q, name == 'direct' ? 'distribution' : 'direct')['limit']);
    return value != null && (other == null || value >= other);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final filtered = items.where((q) =>
        (category == '全部' || q['category'] == category) &&
        (!excludeC || quotaShareClass('${q['name']}') != 'C') &&
        '${q['name']} ${q['code']}'.toLowerCase().contains(query.toLowerCase())).toList();
    // Sort by each fund's own quota first. Only equal quota values use the
    // family name and share-class letter as tie-breakers, keeping equal-limit
    // A/C/D/I share classes together with A first.
    final families = {for (final q in filtered) '${q['code']}': quotaFamilyName('${q['name']}')};
    filtered.sort((a, b) {
      final av = sort == 'name' ? '${a['name']}' : sortValue(a);
      final bv = sort == 'name' ? '${b['name']}' : sortValue(b);
      var result = av is num && bv is num ? av.compareTo(bv) : '$av'.compareTo('$bv');
      if (result != 0) return ascending ? result : -result;

      final familyA = families['${a['code']}']!, familyB = families['${b['code']}']!;
      result = familyA.compareTo(familyB);
      if (result != 0) return result;
      result = shareClassRank(a).compareTo(shareClassRank(b));
      if (result != 0) return result;
      result = '${a['name']}'.compareTo('${b['name']}');
      return result == 0 ? '${a['code']}'.compareTo('${b['code']}') : result;
    });

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
    const double h = 40;
    const double r = 20;
    final fill = scheme.surfaceContainerHighest.withValues(alpha: 0.6);
    final iconColor = scheme.onSurfaceVariant;

    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(
        child: Container(
          height: h,
          decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(r)),
          alignment: Alignment.center,
          child: TextField(
            decoration: InputDecoration(
              hintText: '搜索基金',
              hintStyle: theme.textTheme.bodySmall?.copyWith(color: iconColor),
              prefixIcon: Icon(Icons.search, size: 18, color: iconColor),
              prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 24),
              border: InputBorder.none,
              isCollapsed: true,
            ),
            style: theme.textTheme.bodySmall,
            textAlignVertical: TextAlignVertical.center,
            onChanged: (value) => setState(() => query = value),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Material(
        color: excludeC ? scheme.primaryContainer : fill,
        borderRadius: BorderRadius.circular(r),
        child: InkWell(
          borderRadius: BorderRadius.circular(r),
          onTap: () => setState(() => excludeC = !excludeC),
          child: Container(
            height: h,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            child: Text('排除C', style: theme.textTheme.labelMedium?.copyWith(
              color: excludeC ? scheme.onPrimaryContainer : iconColor,
              fontWeight: excludeC ? FontWeight.w600 : FontWeight.normal,
            )),
          ),
        ),
      ),
      const SizedBox(width: 8),
      PopupMenuButton<String>(
        tooltip: '排序方式',
        initialValue: sort,
        onSelected: (value) => setState(() => sort = value),
        itemBuilder: (context) => [for (final option in sortOptions) PopupMenuItem(value: option.$1, child: Text(option.$2))],
        child: Container(
          height: h,
          decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(r)),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
            Icon(Icons.sort, size: 16, color: iconColor),
            const SizedBox(width: 4),
            Text(sortOptions.firstWhere((o) => o.$1 == sort).$2, style: theme.textTheme.labelMedium?.copyWith(color: iconColor)),
            Icon(Icons.arrow_drop_down, size: 16, color: iconColor),
          ]),
        ),
      ),
      const SizedBox(width: 8),
      Material(
        color: fill,
        borderRadius: BorderRadius.circular(r),
        child: InkWell(
          borderRadius: BorderRadius.circular(r),
          onTap: () => setState(() => ascending = !ascending),
          child: SizedBox(
            height: h,
            width: h,
            child: Icon(ascending ? Icons.arrow_upward : Icons.arrow_downward, size: 17, color: iconColor),
          ),
        ),
      ),
    ]);
  }

  Widget _buildQuotaCard(ThemeData theme, ColorScheme scheme, Quota q) {
    final annual = q['annualReturn'] == null ? null : num.tryParse('${q['annualReturn']}');
    final userOverride = q['valueSource'] == 'user';

    return Card(
      elevation: 0,
      color: scheme.surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : () => edit(q),
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
                _channelLine(theme, scheme, '代销', channel(q, 'distribution'), highlight: _highlightChannel(q, 'distribution')),
                const SizedBox(height: 2),
                _channelLine(theme, scheme, '直销', channel(q, 'direct'), highlight: _highlightChannel(q, 'direct')),
                const SizedBox(height: 4),
                Text('费率 ${_feeRateText(q)}', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ]),
            ]),
            Row(children: [
              Transform.translate(offset: const Offset(-10, 0), child: _cardAction(theme, scheme, '修改', busy ? null : () => edit(q))),
              if (userOverride) _cardAction(theme, scheme, '恢复自动', busy ? null : () => run(() => widget.repository.restore('${q['code']}'))),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _channelLine(ThemeData theme, ColorScheme scheme, String label, QuotaChannel value, {bool highlight = false}) => Row(mainAxisSize: MainAxisSize.min, children: [
    Text('${label} ', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontWeight: highlight ? FontWeight.w700 : null)),
    Text(_channelValueText(value), style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontWeight: highlight ? FontWeight.w700 : null)),
  ]);

  String _channelValueText(QuotaChannel value) {
    final status = '${value['status'] ?? '未知'}';
    if (status == '限大额') return _limitText(value);
    if (status == '未知') return '未披露';
    return status;
  }

  String _limitText(QuotaChannel value) {
    final raw = quotaAmount(value['limit']);
    if (raw == null) return '-';
    if (raw >= 100000000) return '${(raw / 100000000).toStringAsFixed(raw % 100000000 == 0 ? 0 : 2)}亿';
    if (raw >= 10000) return '${(raw / 10000).toStringAsFixed(raw % 10000 == 0 ? 0 : 2)}万';
    return raw.toStringAsFixed(0);
  }

  String _feeRateText(Quota q) {
    final value = num.tryParse('${q['feeRate']}');
    return value == null ? '-' : '${(value * 100).toStringAsFixed(2)}%';
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
