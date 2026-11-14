import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'local_cache_store.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();

  DatabaseService._internal();

  // In-memory persistent fallback store matching Firestore document structure:
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

  // Collections mirrored to disk so profiles and onboarding state survive
  // logouts, browser reloads and Firestore permission-denied responses.
  static const Set<String> _persistedCollections = {
    'users',
    'settings',
    'matches',
    'listings',
  };
  static const String _cacheKeyPrefix = 'database_cache_v2_';
  static const String _subcollectionCacheKey =
      'database_cache_v2_subcollections';

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

  // Normalises values (DateTime, enums, nested maps) into JSON-safe primitives.
  static dynamic _jsonSafe(dynamic value) {
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (value is DateTime) return value.millisecondsSinceEpoch;
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is Enum) return value.name;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _jsonSafe(v)));
    }
    if (value is Iterable) return value.map(_jsonSafe).toList();
    return value.toString();
  }

  /// Prefers the locally cached document when it is newer than the cloud copy.
  /// This prevents a stale Firestore profile from resetting onboarding state.
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
    // Keep tests isolated from previously hydrated data without touching the
    // real persistent store, and skip plugin-backed writes that would leave
    // pending timers in widget tests.
    _persistenceDisabledForTesting = true;
    _cacheHydration = null;
  }

  bool get isFirebaseAvailable {
    try {
      if (Firebase.apps.isEmpty) return false;
      final app = Firebase.app();
      final key = app.options.apiKey;
      final project = app.options.projectId;
      // If placeholder or demo options, safely use local resilient database engine
      if (key.contains('Placeholder') ||
          key.isEmpty ||
          project.contains('placeholder') ||
          project == 'rently-app-mvp') {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  FirebaseFirestore? get firestore {
    if (isFirebaseAvailable) {
      try {
        return FirebaseFirestore.instance;
      } catch (e) {
        debugPrint('[DatabaseService] Firestore access error: $e');
        return null;
      }
    }
    return null;
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
    //    Cloud Firestore later rejects the write with permission-denied.
    unawaited(_persistCollection(collection));

    // 3. Cloud Firestore sync with non-blocking timeout if configured
    final fs = firestore;
    if (fs == null) return true;
    try {
      await fs
          .collection(collection)
          .doc(docId)
          .set(data, SetOptions(merge: merge))
          .timeout(const Duration(seconds: 3));
      return true;
    } catch (e) {
      debugPrint(
        '[DatabaseService] Cloud Firestore write failed for '
        '$collection/$docId; kept in the local cache and will retry on the '
        'next sync: $e',
      );
      return false;
    }
  }

  /// Removes a document locally and in Firestore. Returns `false` when the
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

    final fs = firestore;
    if (fs == null) return true;
    try {
      await fs
          .collection(collection)
          .doc(docId)
          .delete()
          .timeout(const Duration(seconds: 3));
      return true;
    } catch (e) {
      debugPrint(
        '[DatabaseService] Cloud Firestore delete failed for '
        '$collection/$docId; removed from the local cache only: $e',
      );
      return false;
    }
  }

  Future<Map<String, dynamic>?> getDocument({
    required String collection,
    required String docId,
  }) async {
    final local = _localCollections[collection]?[docId];
    final fs = firestore;
    if (fs != null) {
      try {
        final snap = await fs.collection(collection).doc(docId).get();
        if (snap.exists && snap.data() != null) {
          final resolved = _preferNewest(snap.data()!, local);
          _localCollections.putIfAbsent(collection, () => {})[docId] = resolved;
          unawaited(_persistCollection(collection));
          return resolved;
        }
      } catch (e) {
        debugPrint(
            '[DatabaseService] Cloud Firestore read failed, checking local store: $e');
      }
    }

    return local;
  }

  /// Reads only the durable local mirror, without touching Cloud Firestore.
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

  /// Immediately mirrors a document into the durable local cache without
  /// waiting on Cloud Firestore. Used for mock/sample profiles so onboarding
  /// state is durable even when the cloud write is rejected.
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
    final fs = firestore;
    if (fs == null) {
      return _localDocumentStream(collection, docId);
    }
    return _firestoreDocumentStream(fs, collection, docId);
  }

  /// Streams a whole collection, optionally narrowed by one equality filter and
  /// one array-contains filter. Results are unordered; repositories sort them so
  /// the app does not need composite Firestore indexes.
  Stream<List<Map<String, dynamic>>> streamCollection({
    required String collection,
    String? whereField,
    Object? isEqualTo,
    String? arrayContainsField,
    Object? arrayContainsValue,
    int? limit,
  }) {
    final fs = firestore;
    if (fs == null) {
      return _localCollectionStream(
        collection,
        whereField: whereField,
        isEqualTo: isEqualTo,
        arrayContainsField: arrayContainsField,
        arrayContainsValue: arrayContainsValue,
      );
    }
    return _firestoreCollectionStream(
      fs,
      collection,
      whereField: whereField,
      isEqualTo: isEqualTo,
      arrayContainsField: arrayContainsField,
      arrayContainsValue: arrayContainsValue,
      limit: limit,
    );
  }

  Stream<Map<String, dynamic>?> _firestoreDocumentStream(
    FirebaseFirestore fs,
    String collection,
    String docId,
  ) async* {
    try {
      await for (final snap
          in fs.collection(collection).doc(docId).snapshots()) {
        final data = snap.data();
        if (data != null) {
          final resolved =
              _preferNewest(data, _localCollections[collection]?[docId]);
          _localCollections.putIfAbsent(collection, () => {})[docId] = resolved;
          unawaited(_persistCollection(collection));
          yield resolved;
        } else {
          yield _localCollections[collection]?[docId];
        }
      }
    } catch (e) {
      debugPrint(
          '[DatabaseService] Firestore document stream failed, using local store: $e');
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

  Stream<List<Map<String, dynamic>>> _firestoreCollectionStream(
    FirebaseFirestore fs,
    String collection, {
    String? whereField,
    Object? isEqualTo,
    String? arrayContainsField,
    Object? arrayContainsValue,
    int? limit,
  }) async* {
    try {
      Query<Map<String, dynamic>> query = fs.collection(collection);
      if (whereField != null && isEqualTo != null) {
        query = query.where(whereField, isEqualTo: isEqualTo);
      }
      if (arrayContainsField != null && arrayContainsValue != null) {
        query = query.where(
          arrayContainsField,
          arrayContains: arrayContainsValue,
        );
      }
      if (limit != null) query = query.limit(limit);

      await for (final snap in query.snapshots()) {
        final docs =
            snap.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
        _localCollections.putIfAbsent(collection, () => {});
        for (final doc in snap.docs) {
          _localCollections[collection]![doc.id] = doc.data();
        }
        unawaited(_persistCollection(collection));
        yield docs;
      }
    } catch (e) {
      debugPrint(
        '[DatabaseService] Firestore collection stream failed for '
        '$collection, using local store: $e',
      );
      yield* _localCollectionStream(
        collection,
        whereField: whereField,
        isEqualTo: isEqualTo,
        arrayContainsField: arrayContainsField,
        arrayContainsValue: arrayContainsValue,
      );
    }
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
        .where((data) {
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
        })
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

  Future<void> setSubdocument({
    required String parentCollection,
    required String parentId,
    required String subcollection,
    required String docId,
    required Map<String, dynamic> data,
  }) async {
    // 1. Immediately update local subcollection store
    final path = '$parentCollection/$parentId/$subcollection';
    _localSubcollections.putIfAbsent(path, () => {});
    _localSubcollections[path]![docId] = Map<String, dynamic>.from(data);
    _notifyCollection(path);
    unawaited(_persistSubcollections());

    // 2. Cloud Firestore sync with timeout if active
    final fs = firestore;
    if (fs != null) {
      try {
        await fs
            .collection(parentCollection)
            .doc(parentId)
            .collection(subcollection)
            .doc(docId)
            .set(data, SetOptions(merge: true))
            .timeout(const Duration(seconds: 3));
      } catch (e) {
        debugPrint(
            '[DatabaseService] Firestore subdocument write skipped/fallback: $e');
      }
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
    final fs = firestore;
    if (fs != null) {
      try {
        final snap = await fs
            .collection(parentCollection)
            .doc(parentId)
            .collection(subcollection)
            .doc(docId)
            .get();
        if (snap.exists && snap.data() != null) {
          _localSubcollections.putIfAbsent(path, () => {})[docId] =
              Map<String, dynamic>.from(snap.data()!);
          unawaited(_persistSubcollections());
          return Map<String, dynamic>.from(snap.data()!);
        }
      } catch (e) {
        debugPrint('[DatabaseService] Firestore subdocument read failed: $e');
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
    final fs = firestore;
    if (fs != null) {
      try {
        final snap = await fs
            .collection(parentCollection)
            .doc(parentId)
            .collection(subcollection)
            .get();
        if (snap.docs.isNotEmpty) {
          _localSubcollections[path] = {
            for (final doc in snap.docs) doc.id: doc.data(),
          };
          unawaited(_persistSubcollections());
          return snap.docs.map((d) => d.data()).toList();
        }
      } catch (e) {
        debugPrint('[DatabaseService] Firestore subcollection read failed: $e');
      }
    }

    return _localSubcollections[path]?.values.toList() ?? [];
  }

  Stream<List<Map<String, dynamic>>> streamSubcollection({
    required String parentCollection,
    required String parentId,
    required String subcollection,
  }) {
    final fs = firestore;
    if (fs == null) {
      return _localSubcollectionStream(
          parentCollection, parentId, subcollection);
    }
    return _firestoreSubcollectionStream(
      fs,
      parentCollection,
      parentId,
      subcollection,
    );
  }

  Stream<List<Map<String, dynamic>>> _firestoreSubcollectionStream(
    FirebaseFirestore fs,
    String parentCollection,
    String parentId,
    String subcollection,
  ) async* {
    final path = '$parentCollection/$parentId/$subcollection';
    try {
      await for (final snap in fs
          .collection(parentCollection)
          .doc(parentId)
          .collection(subcollection)
          .snapshots()) {
        final docs = snap.docs.map((d) => d.data()).toList();
        _localSubcollections[path] = {
          for (final doc in snap.docs) doc.id: doc.data(),
        };
        unawaited(_persistSubcollections());
        yield docs;
      }
    } catch (e) {
      debugPrint(
          '[DatabaseService] Firestore subcollection stream failed, using local store: $e');
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
