import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../domain/user_model.dart';
import '../../../core/services/database_service.dart';

final authDatabaseRepositoryProvider = Provider<AuthDatabaseRepository>((ref) {
  return AuthDatabaseRepository();
});

class AuthDatabaseRepository {
  final DatabaseService _db = DatabaseService.instance;

  FirebaseAuth? get firebaseAuth {
    if (_db.isFirebaseAvailable) {
      try {
        return FirebaseAuth.instance;
      } catch (e) {
        debugPrint('[AuthDatabaseRepository] FirebaseAuth unavailable: $e');
        return null;
      }
    }
    return null;
  }

  /// Persists a profile to the local cache and Firestore.
  ///
  /// Returns `true` when the cloud write succeeded (or when running without
  /// Firestore). A `false` result means the profile is still safe in the
  /// durable local cache and will be retried on the next sign-in.
  Future<bool> saveUserProfile(UserModel user) async {
    // Mock/local identities have no Firebase Auth user, so Firestore must
    // never be touched for them. The durable local cache is authoritative.
    if (firebaseAuth == null) {
      await cacheUserProfileLocally(user);
      return true;
    }

    final map = user.toMap();
    map['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    final persisted = await _db.setDocument(
      collection: 'users',
      docId: user.uid,
      data: map,
    );
    if (!persisted) {
      debugPrint(
        '[Auth] users/${user.uid} is cached locally but not yet in Firestore; '
        'it will be retried on the next sign-in.',
      );
    }
    return persisted;
  }

  Future<UserModel?> fetchUserProfile(String uid) async {
    final data = await _db.getDocument(collection: 'users', docId: uid);
    if (data == null) return null;
    return UserModel.fromMap(data, uid);
  }

  /// Reads only the durable local mirror. Mock/demo identities use this so
  /// they never trigger Firestore reads or writes.
  Future<UserModel?> fetchLocalUserProfile(String uid) async {
    final data = await _db.getLocalDocument(collection: 'users', docId: uid);
    if (data == null) return null;
    return UserModel.fromMap(data, uid);
  }

  /// Re-uploads a cached profile when the Firestore document is missing.
  ///
  /// This repairs accounts that signed in while rules or network access were
  /// failing: the local cache still has the profile, but `users/{uid}` was
  /// never created.
  Future<void> ensureProfileInCloud(UserModel user) async {
    final fs = _db.firestore;
    if (fs == null) return;
    try {
      final snapshot = await fs
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(const Duration(seconds: 5));
      final cloud = snapshot.data();
      final local = await _db.getLocalDocument(
        collection: 'users',
        docId: user.uid,
      );

      final cloudUpdatedAt = cloud?['updatedAt'];
      final localUpdatedAt = local?['updatedAt'];
      final localIsNewer = localUpdatedAt is num &&
          cloudUpdatedAt is num &&
          localUpdatedAt > cloudUpdatedAt;

      if (snapshot.exists && !localIsNewer) return;

      debugPrint(
        snapshot.exists
            ? '[Auth] users/${user.uid} is older than the local cache; '
                're-uploading the cached profile.'
            : '[Auth] users/${user.uid} is missing in Firestore; re-uploading '
                'the cached profile.',
      );
      await saveUserProfile(user);
    } catch (e) {
      debugPrint('[Auth] Profile cloud check failed for users/${user.uid}: $e');
    }
  }

  /// Persists the profile to the durable local cache only, without waiting for
  /// a Cloud Firestore roundtrip.
  Future<void> cacheUserProfileLocally(UserModel user) async {
    final map = user.toMap();
    map['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    await _db.cacheDocumentLocally(
      collection: 'users',
      docId: user.uid,
      data: map,
    );
  }

  Stream<UserModel?> streamUserProfile(String uid) {
    return _db.streamDocument(collection: 'users', docId: uid).map((data) {
      if (data == null) return null;
      return UserModel.fromMap(data, uid);
    });
  }
}
