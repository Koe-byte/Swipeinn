import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_cache_store.dart';

/// Where one app-level "collection" actually lives now.
///
/// The vocabulary came from Firestore. Each collection maps to a Postgres table
/// plus the columns that identify a row, so [DatabaseService] can stay a generic
/// gateway: callers still pass a collection name, a document id and a map.
class _TableSpec {
  const _TableSpec(this.table, this.primaryKey);

  final String table;
  final List<String> primaryKey;
}

/// Firestore subcollections became flat tables with a foreign key. This is the
/// only place the old path shape is translated.
class _SubcollectionSpec {
  const _SubcollectionSpec({
    required this.table,
    required this.parentColumn,
    required this.primaryKey,
  });

  final String table;

  /// Column holding the parent document id, e.g. `matchId`.
  final String parentColumn;

  final List<String> primaryKey;
}

enum _WriteKind { set, delete, subdocument }

/// A cloud write that failed and is waiting to be replayed.
///
/// Firestore's SDK queued offline writes itself. PostgREST does not, so without
/// this the comment on [DatabaseService.setDocument] about retrying would be a
/// lie and an offline edit would vanish on the next launch.
class _PendingWrite {
  const _PendingWrite({
    required this.kind,
    required this.collection,
    required this.docId,
    this.data = const {},
    this.merge = true,
    this.parentId,
    this.subcollection,
  });

  final _WriteKind kind;
  final String collection;
  final String docId;
  final Map<String, dynamic> data;
  final bool merge;
  final String? parentId;
  final String? subcollection;

  Map<String, dynamic> toJson() => {
        'kind': kind.index,
        'collection': collection,
        'docId': docId,
        'data': data,
        'merge': merge,
        'parentId': parentId,
        'subcollection': subcollection,
      };

  factory _PendingWrite.fromJson(Map<String, dynamic> json) {
    final kindIndex = (json['kind'] as num?)?.toInt() ?? 0;
    final rawData = json['data'];
    return _PendingWrite(
      kind: _WriteKind.values[
          kindIndex >= 0 && kindIndex < _WriteKind.values.length
              ? kindIndex
              : 0],
      collection: json['collection'] as String? ?? '',
      docId: json['docId'] as String? ?? '',
      data: rawData is Map
          ? Map<String, dynamic>.from(rawData)
          : const <String, dynamic>{},
      merge: json['merge'] as bool? ?? true,
      parentId: json['parentId'] as String?,
      subcollection: json['subcollection'] as String?,
    );
  }
}

class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();

  DatabaseService._internal();

  static const Map<String, _TableSpec> _tables = {
    'users': _TableSpec('users', ['uid']),
    'listings': _TableSpec('listings', ['id']),
    'listing_likes': _TableSpec('listing_likes', ['listingId', 'requesterUid']),
    'listing_passes': _TableSpec('listing_passes', ['id']),
    'matches': _TableSpec('matches', ['id']),
    'messages': _TableSpec('messages', ['id']),
  };

  static const Map<String, _SubcollectionSpec> _subcollections = {
    'listings/likes': _SubcollectionSpec(
      table: 'listing_likes',
      parentColumn: 'listingId',
      primaryKey: ['listingId', 'requesterUid'],
    ),
    'matches/messages': _SubcollectionSpec(
      table: 'messages',
      parentColumn: 'matchId',
      primaryKey: ['id'],
    ),
  };

  static const Duration _writeTimeout = Duration(seconds: 6);
  static const Duration _readTimeout = Duration(seconds: 6);

  // In-memory persistent fallback store matching the old document structure:
  // collectionPath -> docId -> data map
  final Map<String, Map<String, Map<String, dynamic>>> _localCollections = {
    'users': {},
    'matches': {},
    'settings': {},
  };

  // Subcollections: "matches/{matchId}/messages" -> docId -> data map
  final Map<String, Map<String, Map<String, dynamic>>> _localSubcollections =
      {};

  // Stream controllers for real-time reactivity
  final Map<String, StreamController<Map<String, dynamic>?>> _docControllers =
      {};
  final Map<String, StreamController<List<Map<String, dynamic>>>>
      _colControllers = {};

  final List<_PendingWrite> _pendingWrites = [];

  // Collections mirrored to disk so profiles and onboarding state survive
  // logouts, browser reloads and rejected writes.
  static const Set<String> _persistedCollections = {
    'users',
    'settings',
    'matches',
    'listings',
    'listing_likes',
    'listing_passes',
  };
  // v4 is the Supabase generation. The prefix bump is deliberate: a v3 cache
  // holds Firestore-era rows keyed by Firebase uids, and restoring those would
  // show stale listings from a backend that no longer exists.
  static const String _cacheKeyPrefix = 'database_cache_v4_';
  static const String _subcollectionCacheKey =
      'database_cache_v4_subcollections';
  static const String _pendingWritesKey = 'database_cache_v4_pending_writes';

  final LocalCacheStore _cacheStore = createLocalCacheStore();
  Future<void>? _cacheHydration;
  bool _persistenceDisabledForTesting = false;

  /// Loads the durable mirror into memory exactly once.
  ///
  /// In widget tests the persistence layer is disabled, so this resolves
  /// immediately with a future created in the caller's zone. Completing it
  /// with a future created outside the test's fake-async zone would leave the
  /// caller awaiting forever.
  Future<void> _ensureLocalCacheLoaded() {
    if (_persistenceDisabledForTesting) return Future<void>.value();
    return _cacheHydration ??= _hydrateFromDisk();
  }

  Future<void> _hydrateFromDisk() async {
    try {
      for (final collection in _persistedCollections) {
        final raw = await _cacheStore.read('$_cacheKeyPrefix$collection');
        if (raw == null || raw.isEmpty) continue;
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final store = _localCollections.putIfAbsent(collection, () => {});
        decoded.forEach((docId, data) {
          if (data is Map) {
            // Never clobber a fresher in-memory write made before hydration.
            store.putIfAbsent(
                docId.toString(), () => Map<String, dynamic>.from(data));
          }
        });
      }

      final rawSubcollections = await _cacheStore.read(_subcollectionCacheKey);
      if (rawSubcollections != null && rawSubcollections.isNotEmpty) {
        final decoded = jsonDecode(rawSubcollections);
        if (decoded is Map) {
          decoded.forEach((path, docs) {
            if (docs is! Map) return;
            final store =
                _localSubcollections.putIfAbsent(path.toString(), () => {});
            docs.forEach((docId, data) {
              if (data is Map) {
                store.putIfAbsent(
                    docId.toString(), () => Map<String, dynamic>.from(data));
              }
            });
          });
        }
      }

      final rawPending = await _cacheStore.read(_pendingWritesKey);
      if (rawPending != null && rawPending.isNotEmpty) {
        final decoded = jsonDecode(rawPending);
        if (decoded is List) {
          for (final entry in decoded) {
            if (entry is Map) {
              _pendingWrites.add(
                  _PendingWrite.fromJson(Map<String, dynamic>.from(entry)));
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[DatabaseService] Local cache hydration skipped: $e');
    }
  }

  /// Writes the in-memory collection to disk. No-op for non-persisted collections.
  Future<void> _persistCollection(String collection) async {
    if (!_persistedCollections.contains(collection)) return;
    if (_persistenceDisabledForTesting) return;
    try {
      await _ensureLocalCacheLoaded().timeout(const Duration(seconds: 3));
      final snapshot = (_localCollections[collection] ?? {})
          .map((docId, data) => MapEntry(docId, _jsonSafe(data)));
      await _cacheStore
          .write('$_cacheKeyPrefix$collection', jsonEncode(snapshot))
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('[DatabaseService] Local cache write skipped: $e');
    }
  }

  /// Writes every cached subcollection (matches/*/messages) to disk.
  Future<void> _persistSubcollections() async {
    if (_persistenceDisabledForTesting) return;
    try {
      await _ensureLocalCacheLoaded().timeout(const Duration(seconds: 3));
      final snapshot = _localSubcollections.map(
        (path, docs) => MapEntry(
          path,
          docs.map((docId, data) => MapEntry(docId, _jsonSafe(data))),
        ),
      );
      await _cacheStore
          .write(_subcollectionCacheKey, jsonEncode(snapshot))
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint(
          '[DatabaseService] Local subcollection cache write skipped: $e');
    }
  }

  Future<void> _persistPendingWrites() async {
    if (_persistenceDisabledForTesting) return;
    try {
      await _ensureLocalCacheLoaded().timeout(const Duration(seconds: 3));
      final snapshot = _pendingWrites.map((write) => write.toJson()).toList();
      await _cacheStore
          .write(_pendingWritesKey, jsonEncode(snapshot))
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('[DatabaseService] Pending write cache skipped: $e');
    }
  }

  // Normalises values (DateTime, enums, nested maps) into JSON-safe primitives.
  static dynamic _jsonSafe(dynamic value) {
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (value is DateTime) return value.millisecondsSinceEpoch;
    if (value is Enum) return value.name;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _jsonSafe(v)));
    }
    if (value is Iterable) return value.map(_jsonSafe).toList();
    return value.toString();
  }

  /// Prefers the locally cached document when it is newer than the cloud copy.
  /// This prevents a stale profile from resetting onboarding state.
  static Map<String, dynamic> _preferNewest(
    Map<String, dynamic> cloud,
    Map<String, dynamic>? local,
  ) {
    if (local == null) return cloud;
    final cloudUpdatedAt = cloud['updatedAt'];
    final localUpdatedAt = local['updatedAt'];
    if (cloudUpdatedAt is num &&
        localUpdatedAt is num &&
        localUpdatedAt > cloudUpdatedAt) {
      return local;
    }
    return cloud;
  }

  void resetForTesting() {
    _localCollections.updateAll((_, __) => {});
    _localSubcollections.clear();
    _pendingWrites.clear();
    // Keep tests isolated from previously hydrated data without touching the
    // real persistent store, and skip plugin-backed writes that would leave
    // pending timers in widget tests.
    _persistenceDisabledForTesting = true;
    _cacheHydration = null;
  }

  /// True when a live Supabase client exists and [Supabase.initialize] has run.
  bool get isSupabaseAvailable => _client != null;

  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      // Initialization failed or has not happened yet (widget tests).
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Cloud write plumbing
  // ---------------------------------------------------------------------------

  static Map<String, Object> _documentFilter(_TableSpec spec, String docId) {
    if (spec.primaryKey.length != 1) {
      throw StateError(
          'Collection ${spec.table} needs a composite key and has no root rows.');
    }
    return {spec.primaryKey.first: docId};
  }

  static Map<String, Object> _subdocumentFilter(
    _SubcollectionSpec spec,
    String parentId,
    String docId,
  ) {
    final filter = <String, Object>{spec.parentColumn: parentId};
    if (spec.primaryKey.length == 1) {
      filter[spec.primaryKey.first] = docId;
    } else {
      final idColumn = spec.primaryKey.firstWhere(
        (column) => column != spec.parentColumn,
        orElse: () => spec.primaryKey.last,
      );
      filter[idColumn] = docId;
    }
    return filter;
  }

  static String _subdocumentId(
    _SubcollectionSpec spec,
    Map<String, dynamic> row,
  ) {
    if (spec.primaryKey.length == 1) {
      return row[spec.primaryKey.first]?.toString() ?? '';
    }
    final idColumn = spec.primaryKey.firstWhere(
      (column) => column != spec.parentColumn,
      orElse: () => spec.primaryKey.last,
    );
    return row[idColumn]?.toString() ?? '';
  }

  static String _documentId(_TableSpec spec, Map<String, dynamic> row) {
    return row[spec.primaryKey.first]?.toString() ?? '';
  }

  /// PostgREST's upsert cannot express "merge": a partial row would violate the
  /// NOT NULL columns. So a merge is an UPDATE, falling back to an INSERT only
  /// when the row genuinely does not exist yet.
  ///
  /// Key columns are stripped from the UPDATE body. Postgres checks column
  /// privileges before it compares values, so repeating `"listingId" = ...` in
  /// the SET clause would fail even though the value is unchanged — and the
  /// likes/messages tables deliberately grant UPDATE on only a few columns.
  static Future<void> _writeRow(
    SupabaseClient client,
    String table,
    List<String> primaryKey,
    Map<String, Object> filter,
    Map<String, dynamic> row, {
    required bool merge,
  }) async {
    if (!merge) {
      await client
          .from(table)
          .upsert({...filter, ...row}).timeout(_writeTimeout);
      return;
    }

    final columns = primaryKey.join(',');
    final patch = <String, dynamic>{};
    row.forEach((column, value) {
      final unchangedKey =
          filter.containsKey(column) && filter[column] == value;
      if (!unchangedKey) patch[column] = value;
    });

    if (patch.isNotEmpty) {
      final updated = await client
          .from(table)
          .update(patch)
          .match(filter)
          .select(columns)
          .timeout(_writeTimeout);
      if (updated.isNotEmpty) return;
    } else {
      // Nothing to change: report success if the row is already there.
      final existing = await client
          .from(table)
          .select(columns)
          .match(filter)
          .limit(1)
          .timeout(_writeTimeout);
      if (existing.isNotEmpty) return;
    }

    try {
      await client
          .from(table)
          .insert({...filter, ...row}).timeout(_writeTimeout);
    } on PostgrestException catch (error) {
      // Lost a race: another writer inserted between the update and the
      // insert. Retry the merge once rather than surfacing a false failure.
      if (error.code != '23505') rethrow;
      if (patch.isEmpty) return;
      final retried = await client
          .from(table)
          .update(patch)
          .match(filter)
          .select(columns)
          .timeout(_writeTimeout);
      if (retried.isEmpty) {
        throw StateError('Write to $table was rejected.');
      }
    }
  }

  static Future<void> _executePending(
    SupabaseClient client,
    _PendingWrite write,
  ) async {
    if (write.kind == _WriteKind.subdocument) {
      final spec =
          _subcollections['${write.collection}/${write.subcollection}'];
      if (spec == null) return;
      final parentId = write.parentId;
      if (parentId == null) return;
      final filter = _subdocumentFilter(spec, parentId, write.docId);
      await _writeRow(
        client,
        spec.table,
        spec.primaryKey,
        filter,
        {...write.data, ...filter},
        merge: true,
      );
      return;
    }

    final spec = _tables[write.collection];
    if (spec == null) return;
    final filter = _documentFilter(spec, write.docId);

    if (write.kind == _WriteKind.delete) {
      await client
          .from(spec.table)
          .delete()
          .match(filter)
          .timeout(_writeTimeout);
      return;
    }

    final row = <String, dynamic>{...write.data};
    for (final column in spec.primaryKey) {
      row.putIfAbsent(column, () => filter[column]);
    }
    await _writeRow(
      client,
      spec.table,
      spec.primaryKey,
      filter,
      row,
      merge: write.merge,
    );
  }

  Future<void> _queueWrite(_PendingWrite write) async {
    _pendingWrites.add(write);
    await _persistPendingWrites();
  }

  /// Replays writes that failed while offline. Safe to call more than once.
  Future<void> flushPendingWrites() async {
    final client = _client;
    if (client == null || _pendingWrites.isEmpty) return;

    final queued = List<_PendingWrite>.from(_pendingWrites);
    _pendingWrites.clear();
    var failed = 0;
    for (final write in queued) {
      try {
        await _executePending(client, write);
      } catch (error) {
        failed++;
        _pendingWrites.add(write);
        debugPrint('[DatabaseService] Pending write still failing: $error');
      }
    }
    await _persistPendingWrites();
    if (queued.length > failed) {
      debugPrint('[DatabaseService] Replayed ${queued.length - failed} '
          'pending write(s); $failed still queued.');
    }
  }

  /// Runs one Postgres function through PostgREST.
  ///
  /// Returns `null` when no Supabase client is configured, which lets
  /// repositories fall back to the local mirror in tests and offline builds.
  Future<dynamic> callRpc(
    String function, {
    Map<String, dynamic> params = const {},
  }) {
    final client = _client;
    if (client == null) return Future.value(null);
    return client.rpc(function, params: params).timeout(_writeTimeout);
  }

  // --- Document Operations ---

  Future<bool> setDocument({
    required String collection,
    required String docId,
    required Map<String, dynamic> data,
    bool merge = true,
  }) async {
    // 1. Immediately sync local store for zero-latency UI
    _localCollections.putIfAbsent(collection, () => {});
    if (merge && _localCollections[collection]!.containsKey(docId)) {
      _localCollections[collection]![docId]!.addAll(data);
    } else {
      _localCollections[collection]![docId] = Map<String, dynamic>.from(data);
    }

    _notifyDoc(collection, docId);
    _notifyCollection(collection);

    // 2. Mirror to the durable local cache so profiles (including
    //    hasCompletedOnboarding) survive logouts and browser reloads even if
    //    the cloud write is rejected.
    unawaited(_persistCollection(collection));

    // 3. Supabase sync with non-blocking timeout if configured
    final spec = _tables[collection];
    final client = _client;
    if (spec == null || client == null) return true;

    try {
      final filter = _documentFilter(spec, docId);
      final row = <String, dynamic>{...data};
      for (final column in spec.primaryKey) {
        row.putIfAbsent(column, () => filter[column]);
      }
      await _writeRow(
        client,
        spec.table,
        spec.primaryKey,
        filter,
        row,
        merge: merge,
      );
      unawaited(flushPendingWrites());
      return true;
    } catch (e) {
      debugPrint(
        '[DatabaseService] Supabase write failed for '
        '$collection/$docId; queued for the next sync: $e',
      );
      await _queueWrite(_PendingWrite(
        kind: _WriteKind.set,
        collection: collection,
        docId: docId,
        data: data,
        merge: merge,
      ));
      return false;
    }
  }

  /// Removes a document locally and in the cloud. Returns `false` when the
  /// cloud delete could not be confirmed, so callers can tell the person the
  /// change may not have reached other devices.
  Future<bool> deleteDocument({
    required String collection,
    required String docId,
  }) async {
    _localCollections[collection]?.remove(docId);
    _notifyDoc(collection, docId);
    _notifyCollection(collection);
    unawaited(_persistCollection(collection));

    final spec = _tables[collection];
    final client = _client;
    if (spec == null || client == null) return true;

    try {
      await client
          .from(spec.table)
          .delete()
          .match(_documentFilter(spec, docId))
          .timeout(_writeTimeout);
      unawaited(flushPendingWrites());
      return true;
    } catch (e) {
      debugPrint(
        '[DatabaseService] Supabase delete failed for '
        '$collection/$docId; queued for the next sync: $e',
      );
      await _queueWrite(_PendingWrite(
        kind: _WriteKind.delete,
        collection: collection,
        docId: docId,
      ));
      return false;
    }
  }

  Future<Map<String, dynamic>?> getDocument({
    required String collection,
    required String docId,
  }) async {
    final local = _localCollections[collection]?[docId];
    final spec = _tables[collection];
    final client = _client;
    if (spec != null && client != null) {
      try {
        final data = await client
            .from(spec.table)
            .select()
            .match(_documentFilter(spec, docId))
            .maybeSingle()
            .timeout(_readTimeout);
        if (data != null) {
          final resolved =
              _preferNewest(Map<String, dynamic>.from(data), local);
          _localCollections.putIfAbsent(collection, () => {})[docId] = resolved;
          unawaited(_persistCollection(collection));
          return resolved;
        }
      } catch (e) {
        debugPrint(
            '[DatabaseService] Supabase read failed, checking local store: $e');
      }
    }

    return local;
  }

  /// Reads only the durable local mirror, without touching the cloud.
  /// Used by mock/demo identities that must never perform cloud operations.
  Future<Map<String, dynamic>?> getLocalDocument({
    required String collection,
    required String docId,
  }) async {
    await _ensureLocalCacheLoaded();
    final data = _localCollections[collection]?[docId];
    return data == null ? null : Map<String, dynamic>.from(data);
  }

  /// Hydrates the durable mirror ahead of the first read. Call once from
  /// `main()` after `WidgetsFlutterBinding.ensureInitialized()`.
  Future<void> initializeLocalCache() async {
    try {
      await _ensureLocalCacheLoaded().timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('[DatabaseService] Local cache initialization timed out: $e');
    }
  }

  /// Drops conversation data and queued private writes when the account ends.
  ///
  /// Profiles and public listings stay cached so offline browsing keeps
  /// working, but matches, messages, likes and the pending-write queue belong
  /// to the account that created them. Leaving them behind on a shared device
  /// could show the next account stale private rows or replay its writes as
  /// the wrong user.
  Future<void> clearPrivateState() async {
    _localCollections['matches'] = {};
    _localCollections['listing_likes'] = {};
    _localCollections['listing_passes'] = {};
    _localSubcollections.clear();
    _pendingWrites.clear();

    _notifyCollection('matches');
    _notifyCollection('listing_likes');
    _notifyCollection('listing_passes');
    for (final path
        in _colControllers.keys.where((key) => key.contains('/')).toList()) {
      _notifyCollection(path);
    }

    if (_persistenceDisabledForTesting) return;
    try {
      await _cacheStore.remove('${_cacheKeyPrefix}matches');
      await _cacheStore.remove('${_cacheKeyPrefix}listing_likes');
      await _cacheStore.remove('${_cacheKeyPrefix}listing_passes');
      await _cacheStore.remove(_subcollectionCacheKey);
      await _cacheStore.remove(_pendingWritesKey);
    } catch (e) {
      debugPrint('[DatabaseService] Private cache clear skipped: $e');
    }
  }

  /// Immediately mirrors a document into the durable local cache without
  /// waiting on the cloud. Used for sample profiles so onboarding state is
  /// durable even when the cloud write is rejected.
  Future<void> cacheDocumentLocally({
    required String collection,
    required String docId,
    required Map<String, dynamic> data,
    bool merge = true,
  }) async {
    _localCollections.putIfAbsent(collection, () => {});
    if (merge && _localCollections[collection]!.containsKey(docId)) {
      _localCollections[collection]![docId]!.addAll(data);
    } else {
      _localCollections[collection]![docId] = Map<String, dynamic>.from(data);
    }
    _notifyDoc(collection, docId);
    _notifyCollection(collection);
    // Flush asynchronously; callers must never block on plugin I/O.
    unawaited(_persistCollection(collection));
  }

  Stream<Map<String, dynamic>?> streamDocument({
    required String collection,
    required String docId,
  }) {
    final spec = _tables[collection];
    final client = _client;
    if (spec == null || client == null) {
      return _localDocumentStream(collection, docId);
    }
    return _supabaseDocumentStream(client, collection, spec, docId);
  }

  /// Streams a whole table, optionally narrowed by one equality filter and one
  /// array-contains filter. Results are unordered; repositories sort them so the
  /// app does not need composite indexes.
  ///
  /// Row Level Security already scopes what the signed-in account may see, so
  /// filtering happens client-side and one subscription serves every screen
  /// that watches the same collection.
  Stream<List<Map<String, dynamic>>> streamCollection({
    required String collection,
    String? whereField,
    Object? isEqualTo,
    String? arrayContainsField,
    Object? arrayContainsValue,
    int? limit,
  }) {
    final spec = _tables[collection];
    final client = _client;
    if (spec == null || client == null) {
      return _localCollectionStream(
        collection,
        whereField: whereField,
        isEqualTo: isEqualTo,
        arrayContainsField: arrayContainsField,
        arrayContainsValue: arrayContainsValue,
      );
    }
    return _supabaseCollectionStream(
      client,
      collection,
      spec,
      whereField: whereField,
      isEqualTo: isEqualTo,
      arrayContainsField: arrayContainsField,
      arrayContainsValue: arrayContainsValue,
      limit: limit,
    );
  }

  Stream<Map<String, dynamic>?> _supabaseDocumentStream(
    SupabaseClient client,
    String collection,
    _TableSpec spec,
    String docId,
  ) async* {
    if (spec.primaryKey.length != 1) {
      yield* _localDocumentStream(collection, docId);
      return;
    }
    try {
      final rows = client
          .from(spec.table)
          .stream(primaryKey: spec.primaryKey)
          .eq(spec.primaryKey.first, docId);
      await for (final batch in rows) {
        final row =
            batch.isEmpty ? null : Map<String, dynamic>.from(batch.first);
        if (row != null) {
          final resolved =
              _preferNewest(row, _localCollections[collection]?[docId]);
          _localCollections.putIfAbsent(collection, () => {})[docId] = resolved;
          unawaited(_persistCollection(collection));
          yield resolved;
        } else {
          yield null;
        }
      }
    } catch (e) {
      debugPrint(
          '[DatabaseService] Supabase document stream failed, using local store: $e');
      yield* _localDocumentStream(collection, docId);
    }
  }

  Stream<Map<String, dynamic>?> _localDocumentStream(
      String collection, String docId) {
    final key = '$collection/$docId';
    _docControllers.putIfAbsent(
        key, () => StreamController<Map<String, dynamic>?>.broadcast());
    Future.microtask(() {
      final controller = _docControllers[key];
      if (controller != null && !controller.isClosed) {
        controller.add(_localCollections[collection]?[docId]);
      }
    });
    return _docControllers[key]!.stream;
  }

  Stream<List<Map<String, dynamic>>> _supabaseCollectionStream(
    SupabaseClient client,
    String collection,
    _TableSpec spec, {
    String? whereField,
    Object? isEqualTo,
    String? arrayContainsField,
    Object? arrayContainsValue,
    int? limit,
  }) async* {
    try {
      await for (final rows
          in client.from(spec.table).stream(primaryKey: spec.primaryKey)) {
        final docs = rows.map((row) => Map<String, dynamic>.from(row)).toList();
        final store = _localCollections.putIfAbsent(collection, () => {});
        for (final doc in docs) {
          final id = _documentId(spec, doc);
          if (id.isNotEmpty) store[id] = doc;
        }
        unawaited(_persistCollection(collection));

        var filtered = docs
            .where((doc) => _passesFilters(
                  doc,
                  whereField: whereField,
                  isEqualTo: isEqualTo,
                  arrayContainsField: arrayContainsField,
                  arrayContainsValue: arrayContainsValue,
                ))
            .toList();
        if (limit != null && filtered.length > limit) {
          filtered = filtered.sublist(0, limit);
        }
        yield filtered;
      }
    } catch (e) {
      debugPrint(
        '[DatabaseService] Supabase collection stream failed for '
        '$collection, using local store: $e',
      );

      // Realtime can fail while the REST API still works (disabled
      // publication, websocket blocked by a proxy, expired channel auth).
      // Pull one full snapshot before falling back: otherwise the local mirror
      // only contains rows this device wrote, which makes Discover look like it
      // only ever shows the signed-in account's listings.
      try {
        final rows =
            await client.from(spec.table).select().timeout(_readTimeout);
        final docs = rows.map((row) => Map<String, dynamic>.from(row)).toList();
        final store = _localCollections.putIfAbsent(collection, () => {});
        for (final doc in docs) {
          final id = _documentId(spec, doc);
          if (id.isNotEmpty) store[id] = doc;
        }
        unawaited(_persistCollection(collection));
        debugPrint(
          '[DatabaseService] Recovered $collection snapshot via REST '
          '(${docs.length} rows).',
        );
      } catch (snapshotError) {
        debugPrint(
          '[DatabaseService] REST snapshot also failed for '
          '$collection: $snapshotError',
        );
      }

      yield* _localCollectionStream(
        collection,
        whereField: whereField,
        isEqualTo: isEqualTo,
        arrayContainsField: arrayContainsField,
        arrayContainsValue: arrayContainsValue,
      );
    }
  }

  static bool _passesFilters(
    Map<String, dynamic> data, {
    String? whereField,
    Object? isEqualTo,
    String? arrayContainsField,
    Object? arrayContainsValue,
  }) {
    if (whereField != null &&
        isEqualTo != null &&
        data[whereField] != isEqualTo) {
      return false;
    }
    if (arrayContainsField != null && arrayContainsValue != null) {
      final values = data[arrayContainsField];
      if (values is! Iterable || !values.contains(arrayContainsValue)) {
        return false;
      }
    }
    return true;
  }

  List<Map<String, dynamic>> _localCollectionSnapshot(
    String collection, {
    String? whereField,
    Object? isEqualTo,
    String? arrayContainsField,
    Object? arrayContainsValue,
  }) {
    final docs = _localCollections[collection] ?? const {};
    return docs.values
        .where((data) => _passesFilters(
              data,
              whereField: whereField,
              isEqualTo: isEqualTo,
              arrayContainsField: arrayContainsField,
              arrayContainsValue: arrayContainsValue,
            ))
        .map((data) => Map<String, dynamic>.from(data))
        .toList();
  }

  Stream<List<Map<String, dynamic>>> _localCollectionStream(
    String collection, {
    String? whereField,
    Object? isEqualTo,
    String? arrayContainsField,
    Object? arrayContainsValue,
  }) {
    final controller = _colControllers.putIfAbsent(
      collection,
      () => StreamController<List<Map<String, dynamic>>>.broadcast(),
    );

    // Every listener gets a snapshot on listen, then re-filters each write. The
    // shared controller stays unfiltered because different screens query the
    // same collection with different predicates.
    return () async* {
      List<Map<String, dynamic>> snapshot() => _localCollectionSnapshot(
            collection,
            whereField: whereField,
            isEqualTo: isEqualTo,
            arrayContainsField: arrayContainsField,
            arrayContainsValue: arrayContainsValue,
          );

      yield snapshot();
      await for (final _ in controller.stream) {
        yield snapshot();
      }
    }();
  }

  // --- Subcollection Operations (e.g. matches/{matchId}/messages) ---

  /// Merges a subdocument into the in-memory store without touching the cloud.
  ///
  /// Partial updates (accepting a proposal, approving a like) must not replace
  /// the whole row: doing so used to wipe the message text and sender fields,
  /// which made the proposal bubble disappear locally until Realtime caught up.
  void cacheSubdocumentLocally({
    required String parentCollection,
    required String parentId,
    required String subcollection,
    required String docId,
    required Map<String, dynamic> data,
  }) {
    final path = '$parentCollection/$parentId/$subcollection';
    final store = _localSubcollections.putIfAbsent(path, () => {});
    final existing = store[docId];
    if (existing == null) {
      store[docId] = Map<String, dynamic>.from(data);
    } else {
      existing.addAll(data);
    }
    _notifyCollection(path);
    unawaited(_persistSubcollections());
  }

  Future<bool> setSubdocument({
    required String parentCollection,
    required String parentId,
    required String subcollection,
    required String docId,
    required Map<String, dynamic> data,
  }) async {
    // 1. Merge into the local subcollection store for zero-latency UI.
    cacheSubdocumentLocally(
      parentCollection: parentCollection,
      parentId: parentId,
      subcollection: subcollection,
      docId: docId,
      data: data,
    );

    // 2. Supabase sync with timeout if active.
    final spec = _subcollections['$parentCollection/$subcollection'];
    final client = _client;
    if (spec == null || client == null) return true;

    try {
      final filter = _subdocumentFilter(spec, parentId, docId);
      await _writeRow(
        client,
        spec.table,
        spec.primaryKey,
        filter,
        {...data, ...filter},
        merge: true,
      );
      unawaited(flushPendingWrites());
      return true;
    } catch (e) {
      debugPrint(
          '[DatabaseService] Supabase subdocument write failed; queued: $e');
      await _queueWrite(_PendingWrite(
        kind: _WriteKind.subdocument,
        collection: parentCollection,
        docId: docId,
        data: data,
        parentId: parentId,
        subcollection: subcollection,
      ));
      return false;
    }
  }

  /// Reads one subcollection document. Used to make "like" idempotent without
  /// downloading the whole likes queue.
  Future<Map<String, dynamic>?> getSubdocument({
    required String parentCollection,
    required String parentId,
    required String subcollection,
    required String docId,
  }) async {
    final path = '$parentCollection/$parentId/$subcollection';
    final spec = _subcollections['$parentCollection/$subcollection'];
    final client = _client;
    if (spec != null && client != null) {
      try {
        final data = await client
            .from(spec.table)
            .select()
            .match(_subdocumentFilter(spec, parentId, docId))
            .maybeSingle()
            .timeout(_readTimeout);
        if (data != null) {
          _localSubcollections.putIfAbsent(path, () => {})[docId] =
              Map<String, dynamic>.from(data);
          unawaited(_persistSubcollections());
          return Map<String, dynamic>.from(data);
        }
      } catch (e) {
        debugPrint('[DatabaseService] Supabase subdocument read failed: $e');
      }
    }
    final local = _localSubcollections[path]?[docId];
    return local == null ? null : Map<String, dynamic>.from(local);
  }

  Future<List<Map<String, dynamic>>> getSubcollection({
    required String parentCollection,
    required String parentId,
    required String subcollection,
  }) async {
    final path = '$parentCollection/$parentId/$subcollection';
    final spec = _subcollections['$parentCollection/$subcollection'];
    final client = _client;
    if (spec != null && client != null) {
      try {
        final rows = await client
            .from(spec.table)
            .select()
            .eq(spec.parentColumn, parentId)
            .timeout(_readTimeout);
        if (rows.isNotEmpty) {
          _localSubcollections[path] = {
            for (final row in rows)
              _subdocumentId(spec, Map<String, dynamic>.from(row)):
                  Map<String, dynamic>.from(row),
          };
          unawaited(_persistSubcollections());
          return rows.map((row) => Map<String, dynamic>.from(row)).toList();
        }
      } catch (e) {
        debugPrint('[DatabaseService] Supabase subcollection read failed: $e');
      }
    }

    return _localSubcollections[path]?.values.toList() ?? [];
  }

  Stream<List<Map<String, dynamic>>> streamSubcollection({
    required String parentCollection,
    required String parentId,
    required String subcollection,
  }) {
    final spec = _subcollections['$parentCollection/$subcollection'];
    final client = _client;
    if (spec == null || client == null) {
      return _localSubcollectionStream(
          parentCollection, parentId, subcollection);
    }
    return _supabaseSubcollectionStream(
      client,
      parentCollection,
      parentId,
      subcollection,
      spec,
    );
  }

  Stream<List<Map<String, dynamic>>> _supabaseSubcollectionStream(
    SupabaseClient client,
    String parentCollection,
    String parentId,
    String subcollection,
    _SubcollectionSpec spec,
  ) async* {
    final path = '$parentCollection/$parentId/$subcollection';
    try {
      final rows = client
          .from(spec.table)
          .stream(primaryKey: spec.primaryKey)
          .eq(spec.parentColumn, parentId);
      await for (final batch in rows) {
        final docs =
            batch.map((row) => Map<String, dynamic>.from(row)).toList();
        _localSubcollections[path] = {
          for (final doc in docs) _subdocumentId(spec, doc): doc,
        };
        unawaited(_persistSubcollections());
        yield docs;
      }
    } catch (e) {
      debugPrint(
          '[DatabaseService] Supabase subcollection stream failed, using local store: $e');
      yield* _localSubcollectionStream(
          parentCollection, parentId, subcollection);
    }
  }

  Stream<List<Map<String, dynamic>>> _localSubcollectionStream(
    String parentCollection,
    String parentId,
    String subcollection,
  ) {
    final path = '$parentCollection/$parentId/$subcollection';
    _colControllers.putIfAbsent(
      path,
      () => StreamController<List<Map<String, dynamic>>>.broadcast(),
    );
    Future.microtask(() {
      final controller = _colControllers[path];
      if (controller != null && !controller.isClosed) {
        controller.add(_localSubcollections[path]?.values.toList() ?? []);
      }
    });
    return _colControllers[path]!.stream;
  }

  void _notifyDoc(String collection, String docId) {
    final key = '$collection/$docId';
    final controller = _docControllers[key];
    if (controller != null && !controller.isClosed) {
      controller.add(_localCollections[collection]?[docId]);
    }
  }

  void _notifyCollection(String path) {
    final controller = _colControllers[path];
    if (controller == null || controller.isClosed) return;

    if (path.contains('/')) {
      // Subcollection
      controller.add(_localSubcollections[path]?.values.toList() ?? []);
    } else {
      // Root collection
      controller.add(_localCollections[path]?.values.toList() ?? []);
    }
  }
}
