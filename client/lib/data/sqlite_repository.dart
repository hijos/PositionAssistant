import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'repository.dart';

class SqliteRepository extends _SqliteSession implements Repository {
  SqliteRepository._(this._database) : super(_database);
  final Database _database;

  /// Factory injection allows real SQLite tests without Android method channels.
  static Future<SqliteRepository> open({
    required DatabaseFactory factory,
    required String path,
  }) async {
    final database = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE records (
              collection TEXT NOT NULL,
              id TEXT NOT NULL,
              payload TEXT NOT NULL,
              PRIMARY KEY (collection, id)
            )
          ''');
        },
        // Never erase a newer database with an older app.
        onDowngrade: (db, oldVersion, newVersion) async {
          throw StateError('Unsupported database downgrade: $oldVersion');
        },
      ),
    );
    return SqliteRepository._(database);
  }

  @override
  Future<T> transaction<T>(Future<T> Function(RepositorySession) action) =>
      _database.transaction((txn) => action(_SqliteSession(txn)));

  @override
  Future<void> close() => _database.close();
}

class _SqliteSession implements RepositorySession {
  _SqliteSession(this.executor);
  final DatabaseExecutor executor;

  void _validate(String collection, [String? id]) {
    if (collection.trim().isEmpty || (id != null && id.trim().isEmpty)) {
      throw ArgumentError('Collection and id must not be empty');
    }
  }

  @override
  Future<Map<String, dynamic>?> get(String collection, String id) async {
    _validate(collection, id);
    final rows = await executor.query(
      'records',
      columns: ['payload'],
      where: 'collection = ? AND id = ?',
      whereArgs: [collection, id],
    );
    return rows.isEmpty
        ? null
        : jsonDecode(rows.single['payload'] as String) as Map<String, dynamic>;
  }

  @override
  Future<List<Map<String, dynamic>>> list(String collection) async {
    _validate(collection);
    final rows = await executor.query(
      'records',
      columns: ['payload'],
      where: 'collection = ?',
      whereArgs: [collection],
      orderBy: 'id',
    );
    return rows
        .map(
          (row) => jsonDecode(row['payload'] as String) as Map<String, dynamic>,
        )
        .toList();
  }

  @override
  Future<void> put(
    String collection,
    String id,
    Map<String, dynamic> value,
  ) async {
    _validate(collection, id);
    await executor.insert('records', {
      'collection': collection,
      'id': id,
      'payload': jsonEncode(value),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> delete(String collection, String id) async {
    _validate(collection, id);
    await executor.delete(
      'records',
      where: 'collection = ? AND id = ?',
      whereArgs: [collection, id],
    );
  }
}
