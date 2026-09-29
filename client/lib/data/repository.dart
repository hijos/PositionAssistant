/// Storage boundary shared by local persistence and future remote adapters.
/// Business repositories add typed models and validation above this boundary.
abstract interface class RepositorySession {
  Future<Map<String, dynamic>?> get(String collection, String id);
  Future<List<Map<String, dynamic>>> list(String collection);
  Future<void> put(String collection, String id, Map<String, dynamic> value);
  Future<void> delete(String collection, String id);
}

abstract interface class Repository implements RepositorySession {
  /// Use only the supplied session inside the callback; throwing rolls back.
  Future<T> transaction<T>(
    Future<T> Function(RepositorySession session) action,
  );
  Future<void> close();
}
