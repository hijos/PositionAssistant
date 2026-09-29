import 'fund_search.dart';
import 'import_page.dart';
import 'remote_login.dart';
import 'data/fund_repository.dart';
import 'data/fund_catalog_repository.dart';
import 'data/holding_repository.dart';
import 'data/local_repository.dart';
import 'data/repository.dart';
import 'data/transaction_repository.dart';
import 'data/offline_repository.dart';
import 'offline_pages.dart';
import 'holding_detail.dart';
import 'transaction_entry.dart';
import 'transaction_history.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const PositionAssistantApp());

class PositionAssistantApp extends StatelessWidget {
  const PositionAssistantApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '持仓助手',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff07866f)),
      scaffoldBackgroundColor: const Color(0xfff4f6f8),
      useMaterial3: true,
    ),
    home: const HomeShell(),
  );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int selected = 0;
  bool localMode = !kIsWeb;
  Future<Repository>? localStorage;
  late final LocalFundCatalogRepository localCatalog = LocalFundCatalogRepository(
    () => localStorage ??= openLocalRepository(),
  );
  late final LocalFundRepository localFunds = LocalFundRepository(
    () => localStorage ??= openLocalRepository(),
  );
  RemoteFundRepository? remoteFunds;
  LocalTransactionRepository? localTransactions;
  RemoteTransactionRepository? remoteTransactions;
  LocalHoldingRepository? localHoldings;
  RemoteHoldingRepository? remoteHoldings;
  Future<List<Map<String, dynamic>>>? savedFunds;
  Future<List<Map<String, dynamic>>>? savedHoldings;
  Future<List<Map<String, dynamic>>>? savedPlans;
  late final LocalPlanRepository localPlans = LocalPlanRepository(
    () => localStorage ??= openLocalRepository(),
  );
  FundRepository? get currentFunds => localMode ? localFunds : remoteFunds;
  TransactionRepository? get currentTransactions => localMode
      ? localTransactions ??= LocalTransactionRepository(
          () => localStorage ??= openLocalRepository(),
        )
      : remoteTransactions;
  HoldingRepository? get currentHoldings => localMode
      ? localHoldings ??= LocalHoldingRepository(
          () => localStorage ??= openLocalRepository(),
        )
      : remoteHoldings;
  @override
  void initState() {
    super.initState();
    if (localMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (localMode) localCatalog.refreshIfStale();
        if (mounted) setState(reloadFunds);
      });
    }
  }

  void reloadFunds() {
    savedFunds = currentFunds?.list();
    savedFunds?.ignore();
    savedHoldings = currentHoldings?.list();
    savedHoldings?.ignore();
    savedPlans = localMode ? localPlans.list() : null;
    savedPlans?.ignore();
  }

  Future<void> removeFund(Map<String, dynamic> fund) async {
    final repository = currentFunds;
    if (repository == null) return;
    final name = fund['name'] as String? ?? fund['code'];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除基金'),
        content: Text('确定删除“$name”吗？已有交易记录不会被删除。'),
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
    if (confirmed != true || !mounted) return;
    try {
      await repository.remove(fund['code'] as String);
      if (!mounted) return;
      setState(reloadFunds);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('基金已删除')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$error')),
      );
    }
  }

  Future<void> login() async {
    final token = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const RemoteLoginPage()));
    if (!mounted || token == null) return;
    setState(() {
      remoteFunds?.close();
      remoteTransactions?.close();
      remoteHoldings?.close();
      remoteFunds = RemoteFundRepository(token: token);
      remoteTransactions = RemoteTransactionRepository(token: token);
      remoteHoldings = RemoteHoldingRepository(token: token);
      reloadFunds();
    });
  }

  Future<void> logout() async {
    final old = remoteFunds;
    final oldTransactions = remoteTransactions;
    final oldHoldings = remoteHoldings;
    setState(() {
      remoteFunds = null;
      remoteTransactions = null;
      remoteHoldings = null;
      if (!localMode) savedFunds = null;
    });
    try {
      await old?.logout();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('本机登录已清除，服务端退出请求失败')));
      }
    } finally {
      old?.close();
      oldTransactions?.close();
      oldHoldings?.close();
    }
  }

  Future<void> openSearch() async {
    if (!localMode && remoteFunds == null) await login();
    if (!mounted || currentFunds == null) return;
    final repository = currentFunds!;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FundSearchPage(
          search: localMode ? localCatalog.search : null,
          add: repository.add,
          sourceLabel: localMode ? '本地模式' : '当前远端账号',
        ),
      ),
    );
    if (mounted) setState(reloadFunds);
  }

  Future<void> openTransactionEntry() async {
    if (!localMode && remoteFunds == null) await login();
    if (!mounted) return;
    final transactions = currentTransactions;
    if (transactions == null) return;
    List<Map<String, dynamic>> funds = [];
    try {
      funds = await (currentFunds?.list() ?? Future.value([]));
    } catch (_) {
      // The page still explains that a fund must be added when local storage
      // is unavailable in a preview/test environment.
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            TransactionEntryPage(funds: funds, repository: transactions),
      ),
    );
    if (mounted) setState(reloadFunds);
  }

  Future<void> openTransactionHistory() async {
    if (!localMode && remoteTransactions == null) await login();
    if (!mounted) return;
    final transactions = currentTransactions;
    if (transactions == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TransactionHistoryPage(repository: transactions),
      ),
    );
    if (mounted) setState(reloadFunds);
  }

  Future<void> openHoldingDetails() async {
    if (!localMode && remoteHoldings == null) await login();
    if (!mounted) return;
    final holdings = currentHoldings;
    final transactions = currentTransactions;
    if (holdings == null || transactions == null) return;
    try {
      final items = await holdings.list();
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              HoldingSelectionPage(holdings: items, repository: transactions),
        ),
      );
      if (mounted) setState(reloadFunds);
    } catch (_) {
      if (mounted) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => HoldingSelectionPage(
              holdings: const [],
              repository: transactions,
              errorMessage: '持仓读取失败，请重试',
            ),
          ),
        );
        if (localMode) localCatalog.refreshIfStale();
        if (mounted) setState(reloadFunds);
      }
    }
  }

  Future<void> openHoldingDetail(Map<String, dynamic> holding) async {
    if (!localMode && remoteHoldings == null) await login();
    if (!mounted) return;
    final transactions = currentTransactions;
    if (transactions == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            HoldingDetailPage(holding: holding, repository: transactions),
      ),
    );
    if (mounted) setState(reloadFunds);
  }

  Future<void> openImport() async {
    if (!localMode) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('远端数据导入将在后续版本提供')));
      return;
    }
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            LocalImportPage(open: () => localStorage ??= openLocalRepository()),
      ),
    );
    if (changed == true && mounted) setState(reloadFunds);
  }

  Future<void> openPlans() async {
    if (!localMode || defaultTargetPlatform != TargetPlatform.android) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => LocalPlansPage(open: () => localStorage ??= openLocalRepository())),
    );
    if (mounted) setState(reloadFunds);
  }

  Future<void> openQuotas() async {
    if (!localMode || defaultTargetPlatform != TargetPlatform.android) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => LocalQuotaPage(open: () => localStorage ??= openLocalRepository())),
    );
  }

  Future<void> exportLocal() async {
    if (!localMode || defaultTargetPlatform != TargetPlatform.android) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('远端导出请在登录后使用')));
      return;
    }
    try {
      final json = await exportLocalJson(await (localStorage ??= openLocalRepository()));
      final saved = await const MethodChannel('position_assistant/file_picker').invokeMethod<bool>('saveJsonFile', {'source': json});
      if (mounted && saved == true) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('数据导出成功')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败：$error')));
    }
  }

  @override
  void dispose() {
    remoteFunds?.close();
    remoteTransactions?.close();
    remoteHoldings?.close();
    localCatalog.close();
    localStorage?.then((storage) => storage.close(), onError: (_) {});
    super.dispose();
  }

  Widget fundList() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('已添加基金'),
          if (savedFunds == null)
            TextButton(
              onPressed: () => setState(reloadFunds),
              child: Text(
                !localMode && remoteFunds == null ? '请先登录远端账号' : '读取已添加基金',
              ),
            ),
          if (savedFunds != null)
            FutureBuilder<List<Map<String, dynamic>>>(
              future: savedFunds,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LinearProgressIndicator();
                }
                if (snapshot.hasError) {
                  return TextButton(
                    onPressed: () => setState(reloadFunds),
                    child: const Text('基金列表读取失败，点击重试'),
                  );
                }
                final funds = snapshot.data ?? [];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (funds.isEmpty) const Text('尚未添加基金'),
                    for (final fund in funds)
                      ListTile(
                        title: Text(fund['name'] as String),
                        subtitle: Text('${fund['code']} · ${fund['type']}'),
                        trailing: IconButton(
                          tooltip: '删除基金',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => removeFund(fund),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    ),
  );

  String _money(dynamic value) =>
      value == null ? '—' : '¥${_number(value).toStringAsFixed(2)}';
  double _number(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  String _rate(dynamic value) =>
      value == null ? '—' : '${(_number(value) * 100).toStringAsFixed(2)}%';
  String _estimateLabel(Map<String, dynamic> item) {
    final value = item['estimatedProfit'];
    if (value == null) return item['estimateError']?.toString() ?? '暂无有效估算';
    final source = item['estimateSource']?.toString();
    final date = item['estimateAt']?.toString();
    return '估算收益  ${_money(value)}${source == null ? '' : '\n来源：$source'}${date == null ? '' : '\n更新时间：$date'}';
  }

  Widget holdingOverview() {
    if (savedHoldings == null) {
      return SectionCard(
        title: '持仓概览',
        description:
            '正式市值  —\n正式收益  —\n正式收益率  —\n估算收益（参考）  —\n尚无数据，待确认交易不计入正式收益。',
      );
    }
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: savedHoldings,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SectionCard(title: '持仓概览', description: '正在读取正式市值和收益…');
        }
        if (snapshot.hasError) {
          return SectionCard(
            title: '持仓概览',
            description: '正式市值  —\n正式收益  —\n正式收益率  —\n持仓读取失败：${snapshot.error}',
          );
        }
        final holdings = snapshot.data ?? const <Map<String, dynamic>>[];
        final valued =
            holdings.isNotEmpty &&
            holdings.every(
              (item) => item['marketValue'] != null && item['profit'] != null,
            );
        final cost = holdings.fold<double>(
          0,
          (sum, item) => sum + _number(item['cost']),
        );
        final market = valued
            ? holdings.fold<double>(
                0,
                (sum, item) => sum + _number(item['marketValue']),
              )
            : null;
        final profit = valued
            ? holdings.fold<double>(
                0,
                (sum, item) => sum + _number(item['profit']),
              )
            : null;
        final rate = profit != null && cost > 0 ? profit / cost : null;
        final estimated = holdings
            .map((item) => item['estimatedProfit'])
            .whereType<num>()
            .fold<double>(0, (sum, value) => sum + value.toDouble());
        return Column(
          children: [
            SectionCard(
              title: '持仓概览',
              description:
                  '正式市值  ${_money(market)}\n正式收益  ${_money(profit)}\n正式收益率  ${_rate(rate)}\n估算收益（参考）  ${estimated == 0 ? '—' : _money(estimated)}',
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '当前持仓',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (holdings.isEmpty) const Text('暂无持仓'),
                    for (final item in holdings)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${item['fundName'] ?? item['fundCode'] ?? '基金'}',
                        ),
                        subtitle: Text(
                          '${item['fundCode'] ?? '—'} · ${_number(item['shares']).toStringAsFixed(2)} 份 · 成本 ${_money(item['cost'])}',
                        ),
                        trailing: Text(
                          '${_money(item['marketValue'])}\n正式收益 ${_money(item['profit'])} (${_rate(item['profitRate'])})\n${_estimateLabel(item)}',
                          textAlign: TextAlign.end,
                        ),
                        onTap: () => openHoldingDetail(item),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static const titles = ['持仓', '交易', '定投', '额度', '设置'];
  static const icons = [
    Icons.account_balance_wallet_outlined,
    Icons.swap_horiz,
    Icons.event_repeat,
    Icons.list_alt,
    Icons.settings_outlined,
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('持仓助手 · ${titles[selected]}')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            key: ValueKey(selected),
            padding: const EdgeInsets.all(16),
            children: _content(context),
          ),
        ),
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: selected,
      onDestinationSelected: (value) => setState(() => selected = value),
      destinations: [
        for (var i = 0; i < titles.length; i++)
          NavigationDestination(icon: Icon(icons[i]), label: titles[i]),
      ],
    ),
  );

  List<Widget> _content(BuildContext context) {
    switch (selected) {
      case 0:
        return [
          holdingOverview(),
          fundList(),
          _entry(context, '基金搜索与添加'),
          _entry(context, '持仓详情'),
        ];
      case 1:
        return [
          const SectionCard(title: '交易记录', description: '暂无交易记录'),
          _entry(context, '交易录入'),
          _entry(context, '交易详情'),
        ];
      case 2:
        return [
          FutureBuilder<List<Map<String, dynamic>>>(
            future: savedPlans,
            builder: (context, snapshot) => SectionCard(
              title: '定投计划',
              description: snapshot.hasError
                  ? '定投计划读取失败'
                  : !snapshot.hasData
                      ? '正在读取…'
                      : snapshot.data!.isEmpty
                          ? '暂无定投计划'
                          : '已有 ${snapshot.data!.length} 个计划',
            ),
          ),
          _entry(context, '定投计划编辑'),
        ];
      case 3:
        return [
          const SectionCard(title: '纳斯达克100', description: '暂无额度数据'),
          const SectionCard(title: '标普500', description: '暂无额度数据'),
          _entry(context, '额度详情与手动修改'),
        ];
      default:
        return [
          SectionCard(
            title: '数据模式',
            description: kIsWeb
                ? 'Web 使用远端模式；${remoteFunds == null ? '尚未登录' : '已登录'}。'
                : '${localMode ? '本地' : '远端'}模式；两种模式数据彼此独立。',
          ),
          _modeSetting(),
          _entry(context, '登录'),
          _entry(context, '注册'),
          _entry(context, '退出登录'),

          _entry(context, '数据导入'),
          _entry(context, '数据导出'),
          _entry(context, '覆盖确认'),
        ];
    }
  }

  Widget _modeSetting() => Card(
    child: SwitchListTile(
      title: const Text('本地/远端模式设置'),
      subtitle: Text(localMode ? '当前：本地模式' : '当前：远端模式'),
      value: localMode,
      onChanged: kIsWeb
          ? null
          : (value) => setState(() {
              localMode = value;
              reloadFunds();
            }),
    ),
  );

  Widget _entry(BuildContext context, String title) => Card(
    child: ListTile(
      title: Text(title),
      subtitle: const Text('页面预览'),
      trailing: const Icon(Icons.chevron_right),
      onTap: title == '基金搜索与添加'
          ? openSearch
          : title == '交易录入'
          ? openTransactionEntry
          : title == '交易记录'
          ? openTransactionHistory
          : title == '交易详情'
          ? openTransactionHistory
          : title == '持仓详情'
          ? openHoldingDetails
          : title == '登录'
          ? login
          : title == '退出登录'
          ? logout
          : title == '数据导入'
          ? openImport
          : title == '定投计划编辑' && defaultTargetPlatform == TargetPlatform.android
          ? openPlans
          : title == '额度详情与手动修改' && defaultTargetPlatform == TargetPlatform.android
          ? openQuotas
          : title == '数据导出' && defaultTargetPlatform == TargetPlatform.android
          ? exportLocal
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => title == '基金搜索与添加'
                    ? const FundSearchPage()
                    : PlaceholderPage(title: title),
              ),
            ),
    ),
  );
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.title,
    required this.description,
    super.key,
  });
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Card(
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

class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({required this.title, super.key});
  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          SectionCard(title: '功能准备中', description: '此页面尚未开放，请返回继续浏览。'),
        ],
      ),
    ),
  );
}
