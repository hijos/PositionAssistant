import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/import_repository.dart';
import 'data/repository.dart';

class LocalImportPage extends StatefulWidget {
  const LocalImportPage({required this.open, super.key});

  final Future<Repository> Function() open;

  @override
  State<LocalImportPage> createState() => _LocalImportPageState();
}

class _LocalImportPageState extends State<LocalImportPage> {
  static const _filePicker = MethodChannel('position_assistant/file_picker');
  LocalImportPackage? package;
  String? error;
  bool busy = false;

  Future<void> chooseFile() async {
    setState(() {
      error = null;
      package = null;
    });
    try {
      final source = await _filePicker.invokeMethod<String>('pickJsonFile');
      if (source == null) return;
      final parsed = parseLocalImport(source);
      if (!mounted) return;
      setState(() => package = parsed);
    } catch (exception) {
      if (!mounted) return;
      setState(() => error = _message(exception));
    }
  }

  Future<void> confirmImport() async {
    final selected = package;
    if (selected == null || busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认覆盖本地数据？'),
        content: Text(
          '将替换 ${selected.summary.total} 条记录，包含 '
          '${selected.summary.counts['funds']} 条基金、'
          '${selected.summary.counts['transactions']} 条交易和 '
          '${selected.summary.counts['plans']} 条定投计划。此操作不可撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('覆盖导入'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await importLocalPackage(await widget.open(), selected);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('本地数据导入成功')));
      Navigator.pop(context, true);
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = _message(exception);
      });
    }
  }

  String _message(Object exception) =>
      exception is FormatException ? exception.message : '导入失败，原数据已保留';

  @override
  Widget build(BuildContext context) {
    final selected = package;
    return Scaffold(
      appBar: AppBar(title: const Text('数据导入')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('选择由持仓助手导出的 JSON 文件，确认后将完整覆盖本地 Android 数据。'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: busy ? null : chooseFile,
            icon: const Icon(Icons.upload_file),
            label: const Text('选择 JSON 文件'),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (selected != null) ...[
            const SizedBox(height: 20),
            _SummaryCard(summary: selected.summary),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: busy ? null : confirmImport,
              child: Text(busy ? '正在导入…' : '确认覆盖导入'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final LocalImportSummary summary;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('导入概要', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('导出时间：${summary.exportedAt}'),
          Text('总记录：${summary.total}'),
          for (final collection in importCollections)
            Text('${_label(collection)}：${summary.counts[collection]}'),
          if (summary.fundCodes.isNotEmpty)
            Text('基金代码：${summary.fundCodes.join('、')}'),
        ],
      ),
    ),
  );

  String _label(String collection) => switch (collection) {
    'funds' => '基金',
    'transactions' => '交易',
    'plans' => '定投计划',
    'planEntries' => '定投记录',
    'quotaOverrides' => '额度覆盖',
    _ => collection,
  };
}
