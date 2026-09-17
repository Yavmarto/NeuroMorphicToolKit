abstract interface class WorkspaceCacheStorage {
  Future<String?> read();

  Future<void> write(String value);
}
