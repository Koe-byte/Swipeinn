/// Minimal key/value store used by [DatabaseService] for its durable cache.
///
/// Implementations:
/// - `local_cache_store_io.dart`  -> shared_preferences (mobile/desktop/tests)
/// - `local_cache_store_web.dart` -> window.localStorage (web)
/// - `local_cache_store_stub.dart`-> in-memory (unsupported platforms)
abstract class LocalCacheStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}
