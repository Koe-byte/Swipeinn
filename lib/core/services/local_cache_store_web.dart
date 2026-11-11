// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'local_cache_store_base.dart';

/// localStorage-backed cache for Flutter web. This does not depend on plugin
/// registration, so it keeps working even if the web plugin registrant is stale.
class _WebLocalCacheStore implements LocalCacheStore {
  @override
  Future<String?> read(String key) async => html.window.localStorage[key];

  @override
  Future<void> write(String key, String value) async {
    html.window.localStorage[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    html.window.localStorage.remove(key);
  }
}

LocalCacheStore createLocalCacheStore() => _WebLocalCacheStore();
