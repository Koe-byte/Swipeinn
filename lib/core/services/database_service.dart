import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();

  DatabaseService._internal();

  // In-memory persistent fallback store matching Firestore document structure:
  // collectionPath -> docId -> data map
  final Map<String, Map<String, Map<String, dynamic>>> _localCollections = {
    'users': {},
    'matches': {},
  };

  // Subcollections: "matches/{matchId}/messages" -> docId -> data map
  final Map<String, Map<String, Map<String, dynamic>>> _localSubcollections = {};

  // Stream controllers for real-time reactivity
  final Map<String, StreamController<Map<String, dynamic>?>> _docControllers = {};
  final Map<String, StreamController<List<Map<String, dynamic>>>> _colControllers = {};

  void resetForTesting() {
    _localCollections['users']?.clear();
    _localCollections['matches']?.clear();
    _localSubcollections.clear();
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

  Future<void> setDocument({
    required String collection,
    required String docId,
    required Map<String, dynamic> data,
    bool merge = true,
  }) async {
    // 1. Immediately sync local persistent store for zero-latency UI
    _localCollections.putIfAbsent(collection, () => {});
    if (merge && _localCollections[collection]!.containsKey(docId)) {
      _localCollections[collection]![docId]!.addAll(data);
    } else {
      _localCollections[collection]![docId] = Map<String, dynamic>.from(data);
    }

    _notifyDoc(collection, docId);
    _notifyCollection(collection);

    // 2. Cloud Firestore sync with non-blocking timeout if configured
    final fs = firestore;
    if (fs != null) {
      try {
        await fs
            .collection(collection)
            .doc(docId)
            .set(data, SetOptions(merge: merge))
            .timeout(const Duration(seconds: 3));
      } catch (e) {
        debugPrint('[DatabaseService] Cloud Firestore write skipped/fallback: $e');
      }
    }
  }

  Future<Map<String, dynamic>?> getDocument({
    required String collection,
    required String docId,
  }) async {
    final fs = firestore;
    if (fs != null) {
      try {
        final snap = await fs.collection(collection).doc(docId).get();
        if (snap.exists && snap.data() != null) {
          return snap.data();
        }
      } catch (e) {
        debugPrint('[DatabaseService] Cloud Firestore read failed, checking local store: $e');
      }
    }

    return _localCollections[collection]?[docId];
  }

  Stream<Map<String, dynamic>?> streamDocument({
    required String collection,
    required String docId,
  }) {
    final fs = firestore;
    if (fs != null) {
      return fs.collection(collection).doc(docId).snapshots().map((snap) => snap.data());
    }

    final key = '$collection/$docId';
    _docControllers.putIfAbsent(key, () => StreamController<Map<String, dynamic>?>.broadcast());
    // Emit current value immediately
    Future.microtask(() {
      if (!_docControllers[key]!.isClosed) {
        _docControllers[key]!.add(_localCollections[collection]?[docId]);
      }
    });
    return _docControllers[key]!.stream;
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
        debugPrint('[DatabaseService] Firestore subdocument write skipped/fallback: $e');
      }
    }
  }

  Future<List<Map<String, dynamic>>> getSubcollection({
    required String parentCollection,
    required String parentId,
    required String subcollection,
  }) async {
    final fs = firestore;
    if (fs != null) {
      try {
        final snap = await fs
            .collection(parentCollection)
            .doc(parentId)
            .collection(subcollection)
            .get();
        if (snap.docs.isNotEmpty) {
          return snap.docs.map((d) => d.data()).toList();
        }
      } catch (e) {
        debugPrint('[DatabaseService] Firestore subcollection read failed: $e');
      }
    }

    final path = '$parentCollection/$parentId/$subcollection';
    final docs = _localSubcollections[path]?.values.toList() ?? [];
    return docs;
  }

  Stream<List<Map<String, dynamic>>> streamSubcollection({
    required String parentCollection,
    required String parentId,
    required String subcollection,
  }) {
    final fs = firestore;
    if (fs != null) {
      return fs
          .collection(parentCollection)
          .doc(parentId)
          .collection(subcollection)
          .snapshots()
          .map((snap) => snap.docs.map((d) => d.data()).toList());
    }

    final path = '$parentCollection/$parentId/$subcollection';
    _colControllers.putIfAbsent(path, () => StreamController<List<Map<String, dynamic>>>.broadcast());
    Future.microtask(() {
      if (!_colControllers[path]!.isClosed) {
        final docs = _localSubcollections[path]?.values.toList() ?? [];
        _colControllers[path]!.add(docs);
      }
    });
    return _colControllers[path]!.stream;
  }

  void _notifyDoc(String collection, String docId) {
    final key = '$collection/$docId';
    if (_docControllers.containsKey(key) && !_docControllers[key]!.isClosed) {
      _docControllers[key]!.add(_localCollections[collection]?[docId]);
    }
  }

  void _notifyCollection(String path) {
    if (_colControllers.containsKey(path) && !_colControllers[path]!.isClosed) {
      if (path.contains('/')) {
        // Subcollection
        final docs = _localSubcollections[path]?.values.toList() ?? [];
        _colControllers[path]!.add(docs);
      } else {
        // Root collection
        final docs = _localCollections[path]?.values.toList() ?? [];
        _colControllers[path]!.add(docs);
      }
    }
  }
}
