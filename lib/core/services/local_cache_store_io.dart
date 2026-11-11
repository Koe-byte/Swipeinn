import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_cache_store_base.dart';

/// shared_preferences implementation with an in-memory fallback.
///
/// The fallback keeps tests and unsupported platforms working when the plugin
/// is missing instead of throwing MissingPluginException on every write.
class _PrefsLocalCacheStore implements LocalCacheStore {
  SharedPreferences? _prefs;
  final Map<String, String> _fallback = {};
  bool _pluginWarningLogged = false;

  Future<SharedPreferences?> _getPrefs() async {
    if (_prefs != null) return _prefs;
    try {
      _prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      if (!_pluginWarningLogged && kDebugMode) {
        _pluginWarningLogged = true;
        debugPrint(
          '[LocalCacheStore] shared_preferences unavailable; using the '
          'in-memory cache for this session ($e).',
        );
      }
      _prefs = null;
    }
    return _prefs;
  }

  @override
  Future<String?> read(String key) async {
    final prefs = await _getPrefs();
    return prefs?.getString(key) ?? _fallback[key];
  }

  @override
  Future<void> write(String key, String value) async {
    _fallback[key] = value;
    final prefs = await _getPrefs();
    if (prefs == null) return;
    try {
      await prefs.setString(key, value);
    } catch (e) {
      debugPrint('[LocalCacheStore] write skipped: $e');
    }
  }

  @override
  Future<void> remove(String key) async {
    _fallback.remove(key);
    final prefs = await _getPrefs();
    if (prefs == null) return;
    try {
      await prefs.remove(key);
    } catch (e) {
      debugPrint('[LocalCacheStore] remove skipped: $e');
    }
  }
}

LocalCacheStore createLocalCacheStore() => _PrefsLocalCacheStore();
