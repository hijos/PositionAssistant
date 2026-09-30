import 'dart:async';

import 'format_values.dart';
import 'fund_search.dart';
import 'import_page.dart';
import 'remote_login.dart';
import 'data/fund_repository.dart';
import 'data/fund_catalog_repository.dart';
import 'data/holding_repository.dart';
import 'data/local_repository.dart';
import 'data/nav_repository.dart';
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
  late final LocalFundCatalogRepository localCatalog =
      LocalFundCatalogRepository(() => localStorage ??= openLocalRepository());
  late final LocalFundRepository localFunds = LocalFundRepository(
    () => localStorage ??= openLocalRepository(),
  );
  RemoteFundRepository? remoteFunds;
  LocalTransactionRepository? localTransactions;
  RemoteTransactionRepository? remoteTransactions;
  LocalHoldingRepository? localHoldings;
  LocalNavRepository? localNav;
  RemoteHoldingRepository? remoteHoldings;
  Future<List<Map<String, dynamic>>>? savedFunds;
  Future<List<Map<String, dynamic>>>? savedHoldings;
  late final LocalPlanRepository localPlans = LocalPlanRepository(
    () => localStorage ??= openLocalRepository(),
  );
  // The transactions tab embeds the history page; the shell renders its
  // cleanup action in the app bar (same slot as the watchlist tab's add
  // button), forwards taps through this key, and mirrors the action's
  // enabled/busy state from the notifier.
  final _transactionHistoryKey = GlobalKey<TransactionHistoryPageState>();
  final _transactionCleanup = ValueNotifier<TransactionCleanupState>(
    (busy: false, hasCancelled: false),
  );
  bool _confirmingPending = false;
  FundRepository? get currentFunds => localMode ? localFunds : remoteFunds;
  TransactionRepository? get currentTransactions => localMode
      ? localTransactions ??= LocalTransactionRepository(
          () => localStorage ??= openLocalRepository(),
          nav: localNav ??= LocalNavRepository(
            () => localStorage ??= openLocalRepository(),
          ),
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
        unawaited(_confirmPendingTransactions());
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_confirmPendingTransactions());
      });
    }
  }

  /// Re-check pending trades using the same repository operation as the
  /// manual "重新确认待确认交易" action.  The list check avoids a needless
  /// NAV request when there is nothing to confirm, while the guard prevents
  /// startup and tab-selection callbacks from overlapping.
  Future<void> _confirmPendingTransactions() async {
    if (_confirmingPending) return;
    final repository = currentTransactions;
    if (repository == null) return;
    _confirmingPending = true;
    try {
      final records = await repository.list();
      if (!records.any((item) => item['status'] == 'pending')) return;
      await repository.confirmPending();
      _transactionHistoryKey.currentState?.reload();
      if (mounted) setState(reloadFunds);
    } catch (_) {
      // The transaction page and its manual button surface failures to the
      // user; background refresh should leave the existing records intact.
    } finally {
      _confirmingPending = false;
    }
  }

  void reloadFunds() {
    if (localMode) _refreshLocalNav();
    savedFunds = currentFunds?.list();
    savedFunds?.ignore();
    savedHoldings = currentHoldings?.list();
    savedHoldings?.ignore();
  }

  /// The holdings view derives formal market value and profit from the
  /// fund-level official NAV, which otherwise only advances when a
  /// transaction is confirmed. Refresh it so viewing holdings picks up the
  /// latest published NAV. Failures keep the previous values.
  void _refreshLocalNav() {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final nav = localNav ??= LocalNavRepository(
      () => localStorage ??= openLocalRepository(),
    );
    nav.refreshLatest().then((_) {
      if (!mounted || !localMode) return;
      setState(() {
        savedFunds = localFunds.list()..ignore();
        savedHoldings = currentHoldings?.list();
        savedHoldings?.ignore();
      });
    }, onError: (_) {});
  }

  /// Removes a watchlist entry after the long-press sheet ([FundListTile]) has
  /// picked it. Kept as the destructive step so the confirmation dialog stays
  /// the single owner of the "transactions are not deleted" warning.
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('删除失败：$error')));
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
    unawaited(_confirmPendingTransactions());
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
      MaterialPageRoute(
        builder: (_) =>
            LocalPlansPage(open: () => localStorage ??= openLocalRepository()),
      ),
    );
    if (mounted) setState(reloadFunds);
  }

  Future<void> openQuotas() async {
    if (!localMode || defaultTargetPlatform != TargetPlatform.android) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            LocalQuotaPage(open: () => localStorage ??= openLocalRepository()),
      ),
    );
  }

  Future<void> exportLocal() async {
    if (!localMode || defaultTargetPlatform != TargetPlatform.android) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('远端导出请在登录后使用')));
      }
      return;
    }
    try {
      final json = await exportLocalJson(
        await (localStorage ??= openLocalRepository()),
      );
      final saved = await const MethodChannel('position_assistant/file_picker')
          .invokeMethod<bool>('saveJsonFile', {'source': json});
      if (mounted && saved == true) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('数据导出成功')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出失败：$error')));
      }
    }
  }

  @override
  void dispose() {
    _transactionCleanup.dispose();
    remoteFunds?.close();
    remoteTransactions?.close();
    remoteHoldings?.close();
    localCatalog.close();
    localStorage?.then((storage) => storage.close(), onError: (_) {});
    super.dispose();
  }

  /// The funds the user has added; deletion is reachable by long press only.
  /// Kept separate from [holdingsCard] because a fund can exist without any
  /// confirmed transaction and therefore without a position.
  Widget fundList(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (savedFunds == null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(reloadFunds),
                child: Text(
                  !localMode && remoteFunds == null ? '请先登录远端账号' : '读取自选基金',
                ),
              ),
            )
          else
            FutureBuilder<List<Map<String, dynamic>>>(
              future: savedFunds,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(),
                  );
                }
                if (snapshot.hasError) {
                  return TextButton(
                    onPressed: () => setState(reloadFunds),
                    child: const Text('基金列表读取失败，点击重试'),
                  );
                }
                final funds = snapshot.data ?? const <Map<String, dynamic>>[];
                if (funds.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('暂无自选基金'),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: openSearch,
                          icon: const Icon(Icons.add),
                          label: const Text('添加第一只基金'),
                        ),
                      ],
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final fund in funds)
                      // Same dense rhythm as [HoldingListItem]: the rows sit
                      // back to back instead of leaving a tile's worth of gap.
                      FundListTile(fund: fund, onRemove: removeFund),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '长按基金可删除',
                        style: Theme.of(context).textTheme.bodySmall,
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

  Widget holdingOverview() {
    final future = savedHoldings;
    if (future == null) {
      return const HoldingOverviewCard(
        state: HoldingOverviewState.ready(HoldingOverviewData.empty),
      );
    }
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const HoldingOverviewCard(
            state: HoldingOverviewState.loading(),
          );
        }
        if (snapshot.hasError) {
          return HoldingOverviewCard(
            state: const HoldingOverviewState.error('持仓读取失败，请重试'),
            onRetry: () => setState(reloadFunds),
          );
        }
        return HoldingOverviewCard(
          state: HoldingOverviewState.ready(
            _overviewData(snapshot.data ?? const <Map<String, dynamic>>[]),
          ),
          onRetry: () => setState(reloadFunds),
        );
      },
    );
  }

  /// Aggregates the per-fund holdings into the overview totals.
  ///
  /// Formal value and profit stay `null` unless every holding carries them, so
  /// a missing official NAV never turns into a fake `0`. Rates are derived from
  /// the summed profit over the summed cost instead of averaging per-fund rates.
  HoldingOverviewData _overviewData(List<Map<String, dynamic>> holdings) {
    double? sumWhere(bool Function() hasData, String field) => hasData()
        ? holdings.fold<double>(
            0,
            (sum, item) => sum + parseNumber(item[field]),
          )
        : null;
    final hasFormalValue =
        holdings.isNotEmpty &&
        holdings.every(
          (item) => item['marketValue'] != null && item['profit'] != null,
        );
    final totalCost = holdings.fold<double>(
      0,
      (sum, item) => sum + parseNumber(item['cost']),
    );
    final totalMarketValue = sumWhere(() => hasFormalValue, 'marketValue');
    final totalProfit = sumWhere(() => hasFormalValue, 'profit');
    // "Estimated" follows the same rule but tolerates partial coverage: a fund
    // whose estimate is unavailable simply does not contribute to the total.
    final totalEstimatedMarketValue = sumWhere(
      () => holdings.any((item) => item['estimatedMarketValue'] != null),
      'estimatedMarketValue',
    );
    final totalEstimatedProfit = sumWhere(
      () => holdings.any((item) => item['estimatedProfit'] != null),
      'estimatedProfit',
    );
    double? rateOf(double? profit) =>
        profit == null || totalCost <= 0 ? null : profit / totalCost;
    return HoldingOverviewData(
      totalMarketValue: totalMarketValue,
      totalProfit: totalProfit,
      totalProfitRate: rateOf(totalProfit),
      // Cost always sums cleanly, but an empty ledger reads as missing data
      // (`—`) rather than a fake ￥0.00, same as the other rows.
      totalCost: holdings.isEmpty ? null : totalCost,
      totalEstimatedMarketValue: totalEstimatedMarketValue,
      totalEstimatedProfit: totalEstimatedProfit,
      totalEstimatedProfitRate: rateOf(totalEstimatedProfit),
    );
  }

  /// The per-fund list. Each row is rendered by [HoldingListItem] so the
  /// right-hand figures keep a stable width instead of being squeezed by a
  /// [ListTile] trailing slot.
  Widget holdingsCard(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '当前持仓',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              OutlinedButton.icon(
                onPressed: openTransactionEntry,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加持仓'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (savedHoldings == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('正在读取…'),
            )
          else
            FutureBuilder<List<Map<String, dynamic>>>(
              future: savedHoldings,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(),
                  );
                }
                if (snapshot.hasError) {
                  return TextButton(
                    onPressed: () => setState(reloadFunds),
                    child: const Text('持仓读取失败，点击重试'),
                  );
                }
                final holdings =
                    snapshot.data ?? const <Map<String, dynamic>>[];
                if (holdings.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('暂无持仓'),
                  );
                }
                return Column(
                  children: [
                    for (final item in holdings)
                      HoldingListItem(
                        item: item,
                        onTap: () => openHoldingDetail(item),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    ),
  );

  // 底部导航用简称以控制宽度，顶栏标题用页面全称，两者只有“交易”不同。
  static const titles = ['持仓', '交易', '自选', '额度', '设置'];
  static const pageTitles = ['持仓', '交易记录', '自选', '额度', '设置'];
  static const icons = [
    Icons.account_balance_wallet_outlined,
    Icons.swap_horiz,
    Icons.star_outline,
    Icons.list_alt,
    Icons.settings_outlined,
  ];
  // 「持仓」「设置」两页自身带有标题内容，不再重复显示顶栏。
  static const tabsWithoutAppBar = {0, 4};

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: _appBar(),
    body: SafeArea(
      child: selected == 1
          ? _transactionBody()
          : Center(
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
      onDestinationSelected: (value) {
        setState(() => selected = value);
        if (value == 1) unawaited(_confirmPendingTransactions());
      },
      destinations: [
        for (var i = 0; i < titles.length; i++)
          NavigationDestination(icon: Icon(icons[i]), label: titles[i]),
      ],
    ),
  );

  PreferredSizeWidget? _appBar() {
    if (tabsWithoutAppBar.contains(selected)) return null;
    return AppBar(
      title: Text(pageTitles[selected]),
      actions: selected == 1 && (localMode || remoteTransactions != null)
          ? [
              ValueListenableBuilder<TransactionCleanupState>(
                valueListenable: _transactionCleanup,
                builder: (context, cleanup, _) => Semantics(
                  button: true,
                  label: '清理已取消交易',
                  child: IconButton.filledTonal(
                    onPressed: cleanup.busy || !cleanup.hasCancelled
                        ? null
                        : () => _transactionHistoryKey.currentState
                              ?.clearCancelled(),
                    tooltip: '清理已取消交易',
                    icon: cleanup.busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_sweep_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ]
          : selected == 2
          ? [
              Semantics(
                button: true,
                label: '添加基金',
                child: IconButton.filledTonal(
                  onPressed: openSearch,
                  tooltip: '添加基金',
                  icon: const Icon(Icons.add),
                ),
              ),
              const SizedBox(width: 8),
            ]
          : null,
    );
  }

  Widget _transactionBody() {
    final repository = currentTransactions;
    if (repository == null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('请先登录远端账号'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: login,
                    icon: const Icon(Icons.login),
                    label: const Text('登录'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return TransactionHistoryPage(
      key: _transactionHistoryKey,
      repository: repository,
      embedded: true,
      cleanupState: _transactionCleanup,
    );
  }

  List<Widget> _content(BuildContext context) {
    switch (selected) {
      case 0:
        return [
          holdingOverview(),
          holdingsCard(context),
          _entry(context, '定投计划'),
        ];
      case 2:
        return [fundList(context)];
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
          : title == '定投计划' && defaultTargetPlatform == TargetPlatform.android
          ? openPlans
          : title == '额度详情与手动修改' &&
                defaultTargetPlatform == TargetPlatform.android
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

/// Aggregate totals shown by [HoldingOverviewCard].
///
/// Every field is nullable on purpose: `null` means "no data" and renders as
/// `—`, while a real `0` from the ledger renders as `￥0.00`.
class HoldingOverviewData {
  const HoldingOverviewData({
    required this.totalMarketValue,
    required this.totalProfit,
    required this.totalProfitRate,
    required this.totalCost,
    required this.totalEstimatedMarketValue,
    required this.totalEstimatedProfit,
    required this.totalEstimatedProfitRate,
  });

  static const empty = HoldingOverviewData(
    totalMarketValue: null,
    totalProfit: null,
    totalProfitRate: null,
    totalCost: null,
    totalEstimatedMarketValue: null,
    totalEstimatedProfit: null,
    totalEstimatedProfitRate: null,
  );

  final double? totalMarketValue;
  final double? totalProfit;
  final double? totalProfitRate;
  final double? totalCost;
  final double? totalEstimatedMarketValue;
  final double? totalEstimatedProfit;
  final double? totalEstimatedProfitRate;
}

/// Rendering state of [HoldingOverviewCard].
class HoldingOverviewState {
  const HoldingOverviewState.loading()
    : data = null,
      errorMessage = null,
      isLoading = true;

  const HoldingOverviewState.error(this.errorMessage)
    : data = null,
      isLoading = false;

  const HoldingOverviewState.ready(this.data)
    : errorMessage = null,
      isLoading = false;

  final HoldingOverviewData? data;
  final String? errorMessage;
  final bool isLoading;
}

/// Full-width "持仓概览" card with five label/value rows.
///
/// It is a dedicated widget rather than a [SectionCard] because the figures
/// must be right-aligned in a column of their own, which a single [Text] block
/// cannot express.
class HoldingOverviewCard extends StatelessWidget {
  const HoldingOverviewCard({
    required this.state,
    this.onRetry,
    this.onExplainEstimate,
    super.key,
  });

  final HoldingOverviewState state;
  final VoidCallback? onRetry;
  final VoidCallback? onExplainEstimate;

  @override
  Widget build(BuildContext context) {
    final data = state.data;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('持仓概览', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 18),
            if (state.isLoading) ...const [
              Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              SizedBox(height: 8),
              Text('正在读取…'),
            ] else if (state.errorMessage != null) ...[
              Text(state.errorMessage!),
              if (onRetry != null) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: onRetry,
                    child: const Text('重试'),
                  ),
                ),
              ],
            ] else if (data != null) ...[
              _OverviewRow(
                label: '总市值',
                value: formatMoney(data.totalMarketValue),
              ),
              _OverviewRow(
                label: '总收益',
                value: formatMoneyWithRate(
                  data.totalProfit,
                  data.totalProfitRate,
                ),
                color: profitColor(context, data.totalProfit),
              ),
              _OverviewRow(label: '总成本', value: formatMoney(data.totalCost)),
              _OverviewRow(
                label: '预估市值',
                value: formatMoney(data.totalEstimatedMarketValue),
              ),
              _OverviewRow(
                label: '预估收益',
                value: formatMoneyWithRate(
                  data.totalEstimatedProfit,
                  data.totalEstimatedProfitRate,
                ),
                color: profitColor(context, data.totalEstimatedProfit),
                // Follows the label text as a compact button, so the label
                // keeps the same column and the row the same height as the
                // others while the icon still reads as part of this field.
                trailing: Tooltip(
                  message: '预估收益说明',
                  child: InkWell(
                    onTap: () {
                      final explain = onExplainEstimate;
                      if (explain != null) {
                        explain();
                      } else {
                        showEstimateExplanation(context);
                      }
                    },
                    child: const SizedBox(
                      width: 26,
                      height: 20,
                      child: Icon(Icons.info_outline, size: 18),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Explains where the estimated figures come from.
///
/// A dialog rather than a tooltip: tooltips are not discoverable on touch
/// devices, and the icon must stay usable there.
void showEstimateExplanation(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('预估收益说明'),
    content: const Text('根据美股最新数据估算'),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('知道了'),
      ),
    ],
  ),
);

/// One label/value line of [HoldingOverviewCard].
///
/// The label keeps a fixed width so all figures line up vertically, and the
/// values use the same 18px semibold as the holdings list so the total market
/// value never looks smaller than a single fund's market value. [trailing] is
/// a compact widget drawn right after the label text (the estimate info
/// button); it never moves the label itself, so every row shares one label
/// column whether or not it carries an icon.
class _OverviewRow extends StatelessWidget {
  const _OverviewRow({
    required this.label,
    required this.value,
    this.color,
    this.trailing,
  });

  final String label;
  final String value;
  final Color? color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final trailing = this.trailing;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            // Four CJK characters plus the compact info button.
            width: 112,
            child: Row(
              children: [
                Text(label, style: Theme.of(context).textTheme.bodyMedium),
                if (trailing != null) ...[const SizedBox(width: 4), trailing],
              ],
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One fund position inside the holdings list.
///
/// Left column: fund name, code with shares, cost. Right column: market value,
/// profit with rate, estimated profit. The right column keeps a fixed width so
/// the figures are never squeezed, and the name ellipsizes instead of wrapping.
/// A watchlist row.
///
/// The row keeps no visible delete button so the list stays readable; removal
/// lives behind a long press, which opens a sheet naming the fund before the
/// destructive action is offered.
class FundListTile extends StatelessWidget {
  const FundListTile({required this.fund, required this.onRemove, super.key});

  final Map<String, dynamic> fund;

  /// Runs after the user picks the destructive action in the sheet.
  final Future<void> Function(Map<String, dynamic> fund) onRemove;

  Future<void> openActions(BuildContext context) async {
    final errorColor = Theme.of(context).colorScheme.error;
    final remove = await showModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('${fund['name'] ?? fund['code']}'),
              subtitle: Text('${fund['code']} · ${fund['type']}'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.delete_outline, color: errorColor),
              title: Text('删除基金', style: TextStyle(color: errorColor)),
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
    if (remove == true) await onRemove(fund);
  }

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    visualDensity: VisualDensity.compact,
    title: Text('${fund['name'] ?? fund['code']}'),
    subtitle: Text('${fund['code']} · ${fund['type']}'),
    onLongPress: () => openActions(context),
  );
}

class HoldingListItem extends StatelessWidget {
  const HoldingListItem({required this.item, required this.onTap, super.key});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rightWidth = MediaQuery.sizeOf(context).width < 380 ? 132.0 : 152.0;
    return InkWell(
      onTap: onTap,
      child: Padding(
        // Tight vertical rhythm: consecutive funds are separated by ~16px of
        // white space instead of a full ListTile's worth.
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item['fundName'] ?? item['fundCode'] ?? '基金'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item['fundCode'] ?? '—'}  ${formatNumber(item['shares'])}份',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '成本 ${formatMoney(item['cost'])}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: rightWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatMoney(item['marketValue']),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatMoneyWithRate(item['profit'], item['profitRate']),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 14,
                      color: profitColor(context, item['profit']),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '预估 ${formatMoneyWithRate(item['estimatedProfit'], item['estimatedProfitRate'])}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
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
