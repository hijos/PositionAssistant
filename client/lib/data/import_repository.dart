import 'dart:convert';

import 'repository.dart';

const importCollections = <String>[
  'funds',
  'transactions',
  'plans',
  'planEntries',
  'quotaOverrides',
];

const importFormat = 'position-assistant.export';
const importVersion = 1;

class LocalImportSummary {
  const LocalImportSummary({
    required this.format,
    required this.version,
    required this.exportedAt,
    required this.counts,
    required this.total,
    required this.fundCodes,
    required this.transactionStatuses,
    required this.planEntryStatuses,
  });

  final String format;
  final int version;
  final String exportedAt;
  final Map<String, int> counts;
  final int total;
  final List<String> fundCodes;
  final Map<String, int> transactionStatuses;
  final Map<String, int> planEntryStatuses;
}

class LocalImportPackage {
  const LocalImportPackage({required this.data, required this.summary});

  final Map<String, List<Map<String, dynamic>>> data;
  final LocalImportSummary summary;
}

LocalImportPackage parseLocalImport(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map) throw const FormatException('导入文件必须是 JSON 对象');
  return validateLocalImport(Map<String, dynamic>.from(decoded));
}

LocalImportPackage validateLocalImport(Map<String, dynamic> value) {
  if (value['format'] != importFormat) {
    throw const FormatException('导入文件格式不支持');
  }
  if (value['version'] != importVersion) {
    throw const FormatException('导入文件版本不支持');
  }
  final exportedAt = value['exportedAt'];
  if (exportedAt is! String || DateTime.tryParse(exportedAt) == null) {
    throw const FormatException('导出时间无效');
  }
  final rawData = value['data'];
  if (rawData is! Map) throw const FormatException('导入文件缺少 data 数据');

  final data = <String, List<Map<String, dynamic>>>{};
  for (final collection in importCollections) {
    final rawItems = rawData[collection];
    if (rawItems is! List) {
      throw FormatException('data.$collection 必须是数组');
    }
    final items = <Map<String, dynamic>>[];
    final ids = <String>{};
    for (var index = 0; index < rawItems.length; index++) {
      final rawItem = rawItems[index];
      if (rawItem is! Map) {
        throw FormatException('data.$collection[$index] 必须是对象');
      }
      final item = Map<String, dynamic>.from(rawItem);
      final id = _recordId(collection, item, index);
      if (!ids.add(id)) {
        throw FormatException('data.$collection 存在重复记录：$id');
      }
      items.add(item);
    }
    data[collection] = items;
  }

  final counts = <String, int>{
    for (final collection in importCollections)
      collection: data[collection]!.length,
  };
  final fundCodes = <String>{};
  for (final collection in importCollections) {
    for (final item in data[collection]!) {
      final code = item['code'];
      final fundCode = item['fundCode'];
      if (code is String && code.trim().isNotEmpty) fundCodes.add(code.trim());
      if (fundCode is String && fundCode.trim().isNotEmpty) {
        fundCodes.add(fundCode.trim());
      }
    }
  }
  final total = counts.values.fold<int>(0, (sum, count) => sum + count);
  return LocalImportPackage(
    data: data,
    summary: LocalImportSummary(
      format: importFormat,
      version: importVersion,
      exportedAt: exportedAt,
      counts: counts,
      total: total,
      fundCodes: fundCodes.toList()..sort(),
      transactionStatuses: _countBy(data['transactions']!, 'status'),
      planEntryStatuses: _countBy(data['planEntries']!, 'status'),
    ),
  );
}

String _recordId(String collection, Map<String, dynamic> item, int index) {
  final field = collection == 'funds' || collection == 'quotaOverrides'
      ? 'code'
      : 'id';
  final value = item[field];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('data.$collection[$index] 缺少有效 $field');
  }
  if (collection == 'funds' && !RegExp(r'^\d{6}$').hasMatch(value)) {
    throw FormatException('data.$collection[$index] 基金代码无效');
  }
  return value;
}

Map<String, int> _countBy(Iterable<Map<String, dynamic>> items, String field) {
  final counts = <String, int>{};
  for (final item in items) {
    final value = item[field];
    final key = value == null || value == '' ? 'unknown' : '$value';
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts;
}

Future<LocalImportSummary> importLocalPackage(
  Repository repository,
  LocalImportPackage package,
) async {
  return repository.transaction((session) async {
    for (final collection in importCollections) {
      final existing = await session.list(collection);
      for (final record in existing) {
        await session.delete(collection, _recordId(collection, record, -1));
      }
      for (final record in package.data[collection]!) {
        await session.put(
          collection,
          _recordId(collection, record, -1),
          record,
        );
      }
    }
    return package.summary;
  });
}
