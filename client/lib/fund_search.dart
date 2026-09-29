import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class FundSearchApi {
  FundSearchApi({http.Client? client}) : client = client ?? http.Client();
  final http.Client client;
  Future<List<Map<String, dynamic>>> search(String query) async {
    const configured = String.fromEnvironment('API_BASE_URL');
    final base = configured.isNotEmpty
        ? Uri.parse(configured)
        : kIsWeb
        ? Uri.base
        : Uri.parse('http://127.0.0.1:3000');
    final uri = base
        .resolve('/api/funds/search')
        .replace(queryParameters: {'q': query});
    final response = await client.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw Exception('基金搜索暂时不可用，请稍后重试');
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  void close() => client.close();
}

class FundSearchPage extends StatefulWidget {
  const FundSearchPage({super.key, this.search, this.add, this.sourceLabel});
  final Future<List<Map<String, dynamic>>> Function(String)? search;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)? add;
  final String? sourceLabel;
  @override
  State<FundSearchPage> createState() => _FundSearchPageState();
}

class _FundSearchPageState extends State<FundSearchPage> {
  final controller = TextEditingController();
  final api = FundSearchApi();
  List<Map<String, dynamic>> items = [];
  bool loading = false, searched = false;
  String? error;
  final Set<String> adding = {}, added = {};
  Future<void> addFund(Map<String, dynamic> item) async {
    final code = item['code'] as String;
    setState(() {
      adding.add(code);
    });
    try {
      await widget.add!(item);
      if (!mounted) return;
      setState(() {
        added.add(code);
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('基金已添加')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('添加失败，请检查登录或网络后重试')));
    } finally {
      if (mounted) {
        setState(() {
          adding.remove(code);
        });
      }
    }
  }

  int generation = 0;
  void clearResults() {
    generation++;
    setState(() {
      items = [];
      loading = false;
      searched = false;
      error = null;
    });
  }

  Future<void> submit() async {
    final query = controller.text.trim();
    final current = ++generation;
    setState(() {
      items = [];
      error = null;
      searched = query.isNotEmpty;
      loading = query.isNotEmpty;
    });
    if (query.isEmpty) return;
    try {
      final results = await (widget.search ?? api.search)(query);
      if (!mounted || current != generation) return;
      setState(() {
        items = results;
        loading = false;
      });
    } catch (_) {
      if (!mounted || current != generation) return;
      setState(() {
        error = '基金搜索暂时不可用，请稍后重试';
        loading = false;
      });
    }
  }

  @override
  void dispose() {
    generation++;
    controller.dispose();
    api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('基金搜索与添加')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.sourceLabel != null) Text('添加到：${widget.sourceLabel}'),
        const Text('搜索人民币场外基金。最多显示20项，可输入完整代码缩小范围。'),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          maxLength: 100,
          decoration: const InputDecoration(
            labelText: '基金名称或代码',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => clearResults(),
          onSubmitted: (_) => submit(),
        ),
        FilledButton(
          onPressed: loading ? null : submit,
          child: const Text('搜索'),
        ),
        if (loading) const Center(child: CircularProgressIndicator()),
        if (error != null) Text(error!),
        if (searched && !loading && error == null && items.isEmpty)
          const Text('没有找到符合条件的基金'),
        for (final item in items)
          Card(
            child: ListTile(
              title: Text(item['name'] as String),
              subtitle: Text('${item['code']} · ${item['type']}'),
              trailing: widget.add == null
                  ? null
                  : TextButton(
                      onPressed:
                          adding.contains(item['code']) ||
                              added.contains(item['code'])
                          ? null
                          : () => addFund(item),
                      child: Text(
                        added.contains(item['code'])
                            ? '已添加'
                            : adding.contains(item['code'])
                            ? '添加中'
                            : '添加',
                      ),
                    ),
            ),
          ),
      ],
    ),
  );
}
