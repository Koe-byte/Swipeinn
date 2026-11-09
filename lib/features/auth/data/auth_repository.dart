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

  Future<void> saveUserProfile(UserModel user) async {
    final map = user.toMap();
    map['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    await _db.setDocument(
      collection: 'users',
      docId: user.uid,
      data: map,
    );
  }

  Future<UserModel?> fetchUserProfile(String uid) async {
    final data = await _db.getDocument(collection: 'users', docId: uid);
    if (data == null) return null;
    return UserModel.fromMap(data, uid);
  }

  Stream<UserModel?> streamUserProfile(String uid) {
    return _db.streamDocument(collection: 'users', docId: uid).map((data) {
      if (data == null) return null;
      return UserModel.fromMap(data, uid);
    });
  }
}
