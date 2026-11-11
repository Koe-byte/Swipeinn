import 'local_cache_store_base.dart';

class _MemoryLocalCacheStore implements LocalCacheStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }
}

LocalCacheStore createLocalCacheStore() => _MemoryLocalCacheStore();
