import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'repository.dart';
import 'sqlite_repository.dart';

/// Call after WidgetsFlutterBinding.ensureInitialized().
/// Web must supply a remote Repository; never silently use local storage.
Future<Repository> openLocalRepository() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    throw UnsupportedError('Local storage is supported on Android only');
  }
  return SqliteRepository.open(
    factory: databaseFactory,
    path: p.join(await getDatabasesPath(), 'position_assistant.db'),
  );
}
