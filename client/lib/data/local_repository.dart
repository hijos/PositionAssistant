import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'repository.dart';
import 'sqlite_repository.dart';

const _bundleQuotaData = bool.fromEnvironment(
  'BUNDLE_QUOTA_DATA',
  defaultValue: false,
);

/// Call after WidgetsFlutterBinding.ensureInitialized().
/// Web must supply a remote Repository; never silently use local storage.
Future<Repository> openLocalRepository() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    throw UnsupportedError('Local storage is supported on Android only');
  }
  final repository = await SqliteRepository.open(
    factory: databaseFactory,
    path: p.join(await getDatabasesPath(), 'position_assistant.db'),
  );
  if (_bundleQuotaData) await _seedBundledQuotaData(repository);
  return repository;
}

Future<void> _seedBundledQuotaData(Repository repository) async {
  final seed = jsonDecode(
    await rootBundle.loadString('assets/quota_seed.json'),
  );
  if (seed is! Map || seed['quotas'] is! List) {
    throw const FormatException('内置额度数据格式无效');
  }
  final quotas = (seed['quotas'] as List)
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .where((item) => '${item['code']}'.trim().isNotEmpty)
      .toList();
  if (quotas.isEmpty) return;

  final existing = await repository.list('quotas');
  final meta = await repository.get('quotaServiceMeta', 'state');
  if (existing.isNotEmpty || meta != null) return;

  await repository.transaction((session) async {
    for (final item in quotas) {
      await session.put('quotas', '${item['code']}', item);
    }
    await session.put('quotaServiceMeta', 'state', {
      'version': seed['version'],
      'updatedAt': seed['updatedAt'],
      'source': 'bundled-quota-seed',
    });
  });
}
