import 'package:flutter/material.dart';

import 'data/local_repository.dart';
import 'data/quota_repository.dart';
import 'data/repository.dart';

// Fund names are stored in Chinese. Alphabetical sorting follows each
// character's pinyin reading, mirroring the quota sub-service's zh-CN
// collation, so e.g. 宝盈 (baoying) sorts before 万家 (wanjia) instead of
// Unicode code-point order. The table covers every CJK character in the
// quota fund catalog; unmapped characters keep their raw form and sink after
// Latin-keyed names, so extend the table when the catalog adds new ones.
const _charPinyin = <String, String>{
  '安': 'an',
  '柏': 'bai',
  '宝': 'bao',
  '标': 'biao',
  '币': 'bi',
  '博': 'bo',
  '钞': 'chao',
  '成': 'cheng',
  '达': 'da',
  '大': 'da',
  '等': 'deng',
  '发': 'fa',
  '方': 'fang',
  '富': 'fu',
  '根': 'gen',
  '广': 'guang',
  '国': 'guo',
  '弘': 'hong',
  '华': 'hua',
  '汇': 'hui',
  '家': 'jia',
  '嘉': 'jia',
  '建': 'jian',
  '接': 'jie',
  '克': 'ke',
  '联': 'lian',
  '美': 'mei',
  '民': 'min',
  '摩': 'mo',
  '纳': 'na',
  '南': 'nan',
  '普': 'pu',
  '起': 'qi',
  '权': 'quan',
  '人': 'ren',
  '瑞': 'rui',
  '商': 'shang',
  '时': 'shi',
  '实': 'shi',
  '式': 'shi',
  '数': 'shu',
  '斯': 'si',
  '泰': 'tai',
  '天': 'tian',
  '添': 'tian',
  '万': 'wan',
  '夏': 'xia',
  '信': 'xin',
  '易': 'yi',
  '盈': 'ying',
  '招': 'zhao',
  '指': 'zhi',
  '重': 'zhong',
};

String _pinyinSortKey(String name) {
  final buffer = StringBuffer();
  for (final ch in name.split('')) {
    buffer.write(_charPinyin[ch] ?? ch);
  }
  return buffer.toString();
}

class QuotaPage extends StatefulWidget {
  const QuotaPage({required this.repository, this.refreshToken = 0, super.key});
  final QuotaRepository repository;

  /// 每次点击底部「额度」tab 时递增，触发一次自动刷新。
  final int refreshToken;
  @override
  State<QuotaPage> createState() => _QuotaPageState();
}

class _QuotaPageState extends State<QuotaPage> {
  List<Quota> items = [];
  bool loading = true, busy = false, ascending = false, excludeC = false;
  String? error;
  String query = '', sort = 'directLimit';
  Set<String> selectedCategories = {'纳斯达克100', '标普500'};
  final _queryController = TextEditingController();
  Repository? _preferencesStorage;
  Future<Repository>? _preferencesStorageOpening;
  Future<void> _preferencesWrite = Future<void>.value();

  static const categories = ['纳斯达克100', '标普500'];
  static const _preferencesCollection = 'quotaPagePreferences';
  static const _preferencesId = 'state';
  static const sortOptions = [
    ('directLimit', '按直销额度'),
    ('distributionLimit', '按代销额度'),
    ('maxLimit', '按最大额度'),
    ('name', '按基金名称'),
  ];

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _restorePreferences();
    if (!mounted) return;
    await load();
    if (widget.refreshToken > 0) _autoRefresh();
  }

  Future<Repository> _openPreferencesStorage() {
    final existing = _preferencesStorage;
    if (existing != null) return Future.value(existing);
    return _preferencesStorageOpening ??= openLocalRepository().then((storage) {
      _preferencesStorage = storage;
      return storage;
    });
  }

  Future<void> _restorePreferences() async {
    try {
      final storage = await _openPreferencesStorage();
      final saved = await storage.get(_preferencesCollection, _preferencesId);
      if (!mounted || saved == null) return;
      final rawCategories = saved['categories'];
      final restoredCategories = rawCategories is List
          ? rawCategories
                .map((value) => '$value')
                .where(categories.contains)
                .toSet()
          : <String>{};
      final restoredQuery = '${saved['query'] ?? ''}';
      final restoredSort = '${saved['sort'] ?? ''}';
      final restoredAscending = saved['ascending'] == true;
      final restoredExcludeC = saved['excludeC'] == true;
      setState(() {
        if (restoredCategories.isNotEmpty) {
          selectedCategories = restoredCategories;
        }
        query = restoredQuery;
        sort = sortOptions.any((option) => option.$1 == restoredSort)
            ? restoredSort
            : sort;
        ascending = restoredAscending;
        excludeC = restoredExcludeC;
        _queryController.text = restoredQuery;
        _queryController.selection = TextSelection.collapsed(
          offset: restoredQuery.length,
        );
      });
    } catch (_) {
      // Local preferences are optional on non-Android platforms and in tests.
    }
  }

  void _savePreferences() {
    final snapshot = {
      'categories': selectedCategories.toList(),
      'query': query,
      'sort': sort,
      'ascending': ascending,
      'excludeC': excludeC,
    };
    _preferencesWrite = _preferencesWrite.then((_) async {
      try {
        final storage = await _openPreferencesStorage();
        await storage.put(_preferencesCollection, _preferencesId, snapshot);
      } catch (_) {
        // Local preferences are optional on non-Android platforms and in tests.
      }
    });
  }

  void _updatePreferences(VoidCallback update) {
    setState(update);
    _savePreferences();
  }

  @override
  void dispose() {
    _queryController.dispose();
    final storage = _preferencesStorage;
    if (storage != null) {
      _preferencesWrite.whenComplete(storage.close);
    }
    super.dispose();
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
      if (mounted)
        setState(() {
          items = rows;
          loading = false;
          error = null;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          error = '${e}';
          loading = false;
        });
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
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
    final notice = (widget.repository as CloudQuotaRepository)
        .takeUpdateNotice();
    if (notice != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(notice)));
    }
  });

  QuotaChannel channel(Quota q, String name) {
    final raw = q['channels'];
    final value = raw is Map ? raw[name] : null;
    return normalizeQuotaChannel(
      value is Map ? Map<String, dynamic>.from(value) : null,
      q,
    );
  }

  String _annualReturnText(Quota q) {
    final raw = q['annualReturn'];
    if (raw == null) return '-';
    final value = num.tryParse('${raw}');
    if (value == null) return '-';
    return '${value >= 0 ? '+' : ''}${(value * 100).toStringAsFixed(2)}%';
  }

  String _displayQuotaStatus(Object? raw) {
    final status = '${raw ?? '未知'}';
    return status == '暂停申购' ? '暂停' : status;
  }

  Future<void> edit(Quota q) async {
    String selected = 'direct';
    const statusOptions = ['开放申购', '限大额', '暂停申购'];
    String initialStatus = '${channel(q, selected)['status'] ?? '限大额'}';
    if (initialStatus == '暂停') initialStatus = '暂停申购';
    if (!statusOptions.contains(initialStatus)) initialStatus = '限大额';
    String selectedStatus = initialStatus;
    final limit = TextEditingController(
      text: selectedStatus == '限大额'
          ? '${channel(q, selected)['limit'] ?? ''}'
          : '',
    );
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('修改 ${q['code']}'),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selected,
                    decoration: const InputDecoration(labelText: '额度渠道'),
                    items: const [
                      DropdownMenuItem(
                        value: 'distribution',
                        child: Text('代销渠道'),
                      ),
                      DropdownMenuItem(value: 'direct', child: Text('直销渠道')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      update(() {
                        selected = value;
                        var nextStatus =
                            '${channel(q, selected)['status'] ?? '限大额'}';
                        if (nextStatus == '暂停') nextStatus = '暂停申购';
                        selectedStatus = statusOptions.contains(nextStatus)
                            ? nextStatus
                            : '限大额';
                        limit.text = selectedStatus == '限大额'
                            ? '${channel(q, selected)['limit'] ?? ''}'
                            : '';
                      });
                    },
                  ),
                  DropdownButtonFormField<String>(
                    key: ValueKey(selectedStatus),
                    initialValue: selectedStatus,
                    decoration: const InputDecoration(labelText: '申购状态'),
                    items: [
                      for (final option in statusOptions)
                        DropdownMenuItem(value: option, child: Text(option)),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      update(() {
                        selectedStatus = value;
                        if (value != '限大额') limit.clear();
                      });
                    },
                  ),
                  TextField(
                    controller: limit,
                    enabled: selectedStatus == '限大额',
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '单日限额（元，留空表示未披露）',
                      helperText: selectedStatus == '限大额'
                          ? null
                          : '开放申购和暂停申购不设置单日限额',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '当上传某特定额度的用户足够多时，会自动修正云端额度数据。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            Row(
              children: [
                SizedBox(
                  width: 64,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消', maxLines: 1),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 64,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () => Navigator.pop(context, {
                      'upload': false,
                      'fields': {
                        'channel': selected,
                        'status': quotaStatus(selectedStatus),
                        'limit': selectedStatus == '限大额'
                            ? quotaAmount(limit.text)
                            : null,
                      },
                    }),
                    child: const Text('保存', maxLines: 1),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: () => Navigator.pop(context, {
                      'upload': true,
                      'fields': {
                        'channel': selected,
                        'status': quotaStatus(selectedStatus),
                        'limit': selectedStatus == '限大额'
                            ? quotaAmount(limit.text)
                            : null,
                      },
                    }),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('保存并上传'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    limit.dispose();
    if (result == null || !mounted) return;
    final fields = Map<String, dynamic>.from(result['fields'] as Map);
    final shouldUpload = result['upload'] == true;
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    String? message;
    try {
      await widget.repository.setOverride('${q['code']}', fields);
      if (!shouldUpload) {
        message = '已保存到本机';
      } else {
        final upload = await widget.repository.uploadCorrection(
          '${q['code']}',
          {...fields, 'revision': q['revision']},
        );
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
        if (message != null)
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  dynamic sortValue(Quota q) {
    if (sort == 'directLimit')
      return quotaAmount(channel(q, 'direct')['limit']) ?? -1;
    if (sort == 'distributionLimit')
      return quotaAmount(channel(q, 'distribution')['limit']) ?? -1;
    if (sort == 'maxLimit') {
      final direct = quotaAmount(channel(q, 'direct')['limit']) ?? -1;
      final distribution =
          quotaAmount(channel(q, 'distribution')['limit']) ?? -1;
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
    final other = quotaAmount(
      channel(q, name == 'direct' ? 'distribution' : 'direct')['limit'],
    );
    return value != null && (other == null || value >= other);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final filtered = items
        .where(
          (q) =>
              selectedCategories.contains('${q['category']}') &&
              (!excludeC || quotaShareClass('${q['name']}') != 'C') &&
              '${q['name']} ${q['code']}'.toLowerCase().contains(
                query.toLowerCase(),
              ),
        )
        .toList();
    // Sort by each fund's own quota first. Only equal quota values use the
    // family name and share-class letter as tie-breakers, keeping equal-limit
    // A/C/D/I share classes together with A first. 按基金名称 instead sorts
    // the whole list by the family name's pinyin letters, mirroring the quota
    // sub-service's A-to-Z order.
    final families = {
      for (final q in filtered) '${q['code']}': quotaFamilyName('${q['name']}'),
    };
    String familyKey(Quota q) => _pinyinSortKey(families['${q['code']}']!);
    filtered.sort((a, b) {
      if (sort == 'name') {
        final result = familyKey(a).compareTo(familyKey(b));
        if (result != 0) return ascending ? result : -result;
      } else {
        final av = sortValue(a), bv = sortValue(b);
        final result = av is num && bv is num
            ? av.compareTo(bv)
            : '$av'.compareTo('$bv');
        if (result != 0) return ascending ? result : -result;
        final familyResult = familyKey(a).compareTo(familyKey(b));
        if (familyResult != 0) return familyResult;
      }
      final classResult = shareClassRank(a).compareTo(shareClassRank(b));
      if (classResult != 0) return classResult;
      final nameResult = _pinyinSortKey('${a['name']}')
          .compareTo(_pinyinSortKey('${b['name']}'));
      return nameResult == 0
          ? '${a['code']}'.compareTo('${b['code']}')
          : nameResult;
    });

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _buildCategoryChips(),
            const SizedBox(height: 12),
            _buildToolbar(theme, scheme),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextButton(
                  onPressed: busy ? null : _autoRefresh,
                  child: Text('${error} · 点击重试'),
                ),
              ),
            const SizedBox(height: 12),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!loading && filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('暂无匹配额度；切换到额度页时会自动联网刷新')),
              ),
            for (final q in filtered) _buildQuotaRow(theme, scheme, q),
          ],
        ),
        if (busy && !loading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }

  Widget _buildCategoryChips() {
    final scheme = Theme.of(context).colorScheme;
    int countOf(String c) => items.where((q) => q['category'] == c).length;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final c in categories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('${c} · ${countOf(c)}只'),
                selected: selectedCategories.contains(c),
                showCheckmark: false,
                selectedColor: scheme.primaryContainer,
                labelStyle: TextStyle(
                  fontSize: 14,
                  color: selectedCategories.contains(c)
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                  fontWeight: selectedCategories.contains(c)
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: selectedCategories.contains(c)
                        ? Colors.transparent
                        : scheme.outlineVariant,
                  ),
                ),
                onSelected: (_) {
                  if (selectedCategories.contains(c) &&
                      selectedCategories.length == 1) {
                    return;
                  }
                  _updatePreferences(() {
                    if (selectedCategories.contains(c)) {
                      selectedCategories = {...selectedCategories}..remove(c);
                    } else {
                      selectedCategories = {...selectedCategories, c};
                    }
                  });
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToolbar(ThemeData theme, ColorScheme scheme) {
    const double h = 40;
    const double r = 20;
    final fill = scheme.surfaceContainerHighest.withValues(alpha: 0.6);
    final iconColor = scheme.onSurfaceVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Container(
            height: h,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(r),
            ),
            alignment: Alignment.center,
            child: TextField(
              decoration: InputDecoration(
                hintText: '搜索基金',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: iconColor,
                ),
                prefixIcon: Icon(Icons.search, size: 18, color: iconColor),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 24,
                ),
                border: InputBorder.none,
                isCollapsed: true,
              ),
              style: theme.textTheme.bodyMedium,
              textAlignVertical: TextAlignVertical.center,
              controller: _queryController,
              onChanged: (value) => _updatePreferences(() => query = value),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: excludeC ? scheme.primaryContainer : fill,
          borderRadius: BorderRadius.circular(r),
          child: InkWell(
            borderRadius: BorderRadius.circular(r),
            onTap: () => _updatePreferences(() => excludeC = !excludeC),
            child: Container(
              height: h,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              child: Text(
                '排除C',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: excludeC ? scheme.onPrimaryContainer : iconColor,
                  fontWeight: excludeC ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          tooltip: '排序方式',
          initialValue: sort,
          onSelected: (value) => _updatePreferences(() => sort = value),
          itemBuilder: (context) => [
            for (final option in sortOptions)
              PopupMenuItem(value: option.$1, child: Text(option.$2)),
          ],
          child: Container(
            height: h,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(r),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.sort, size: 16, color: iconColor),
                const SizedBox(width: 4),
                Text(
                  sortOptions.firstWhere((o) => o.$1 == sort).$2,
                  style: theme.textTheme.labelLarge?.copyWith(color: iconColor),
                ),
                Icon(Icons.arrow_drop_down, size: 16, color: iconColor),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: fill,
          borderRadius: BorderRadius.circular(r),
          child: InkWell(
            borderRadius: BorderRadius.circular(r),
            onTap: () => _updatePreferences(() => ascending = !ascending),
            child: SizedBox(
              height: h,
              width: h,
              child: Icon(
                ascending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 17,
                color: iconColor,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuotaRow(ThemeData theme, ColorScheme scheme, Quota q) {
    final annual = q['annualReturn'] == null
        ? null
        : num.tryParse('${q['annualReturn']}');
    final userOverride = q['valueSource'] == 'user';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : () => edit(q),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.65),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  '${q['name']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              _quotaGridRow(
                scheme,
                left: Wrap(
                  spacing: 8,
                  children: [
                    Text(
                      '${q['code']}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '近一年',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      _annualReturnText(q),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: annual == null
                            ? scheme.onSurfaceVariant
                            : _returnColor(annual),
                        fontWeight: annual == null
                            ? FontWeight.normal
                            : FontWeight.w600,
                      ),
                    ),
                    if (userOverride) _badge(scheme, '手动'),
                  ],
                ),
                right: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 10,
                  children: [
                    _channelLine(
                      theme,
                      scheme,
                      '代销',
                      channel(q, 'distribution'),
                      highlight: _highlightChannel(q, 'distribution'),
                    ),
                    _channelLine(
                      theme,
                      scheme,
                      '直销',
                      channel(q, 'direct'),
                      highlight: _highlightChannel(q, 'direct'),
                    ),
                  ],
                ),
              ),
              _quotaGridRow(
                scheme,
                left: Wrap(
                  spacing: 12,
                  runSpacing: 0,
                  children: [
                    _cardAction(
                      theme,
                      scheme,
                      '修改',
                      busy ? null : () => edit(q),
                    ),
                    if (userOverride)
                      _cardAction(
                        theme,
                        scheme,
                        '恢复自动',
                        busy
                            ? null
                            : () => run(
                                () => widget.repository.restore('${q['code']}'),
                              ),
                      ),
                  ],
                ),
                right: Text(
                  '费率 ${_feeRateText(q)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quotaGridRow(
    ColorScheme scheme, {
    required Widget left,
    required Widget right,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(
          child: Align(alignment: Alignment.centerRight, child: right),
        ),
      ],
    ),
  );

  Widget _channelLine(
    ThemeData theme,
    ColorScheme scheme,
    String label,
    QuotaChannel value, {
    bool highlight = false,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '${label} ',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: highlight ? FontWeight.w700 : null,
        ),
      ),
      Text(
        _channelValueText(value),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: highlight ? FontWeight.w700 : null,
        ),
      ),
    ],
  );

  String _channelValueText(QuotaChannel value) {
    final status = '${value['status'] ?? '未知'}';
    if (status == '限大额') return _limitText(value);
    if (status == '未知') return '未披露';
    return _displayQuotaStatus(status);
  }

  String _limitText(QuotaChannel value) {
    final raw = quotaAmount(value['limit']);
    if (raw == null) return '-';
    if (raw >= 100000000)
      return '${(raw / 100000000).toStringAsFixed(raw % 100000000 == 0 ? 0 : 2)}亿';
    if (raw >= 10000)
      return '${(raw / 10000).toStringAsFixed(raw % 10000 == 0 ? 0 : 2)}万';
    return raw.toStringAsFixed(0);
  }

  String _feeRateText(Quota q) {
    final value = num.tryParse('${q['feeRate']}');
    return value == null ? '-' : '${(value * 100).toStringAsFixed(2)}%';
  }

  Widget _badge(ColorScheme scheme, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10,
        color: scheme.onSecondaryContainer,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _cardAction(
    ThemeData theme,
    ColorScheme scheme,
    String label,
    VoidCallback? onPressed,
  ) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      minimumSize: Size.zero,
      padding: const EdgeInsets.symmetric(vertical: 4),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      foregroundColor: scheme.primary,
    ),
    child: Text(
      label,
      style: theme.textTheme.labelMedium?.copyWith(
        color: scheme.primary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Color _returnColor(num value) =>
      value >= 0 ? const Color(0xffc62828) : const Color(0xff2e7d32);
}
