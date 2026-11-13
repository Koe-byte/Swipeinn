import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/auth_state.dart';
import '../domain/user_model.dart';

/// The default backend. Tests override this provider with an in-memory
/// implementation so the suite never needs a live Firebase project.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return FirebaseAuthRepository();
});

/// Everything the app needs from the identity provider and the profile store.
abstract class AuthRepository {
  /// Emits on every Firebase session change, including token refreshes that
  /// flip [AuthIdentity.isEmailVerified].
  Stream<AuthIdentity?> authStateChanges();

  AuthIdentity? get currentIdentity;

  Future<AuthIdentity> signUp({
    required String email,
    required String password,
    required String displayName,
  });

  Future<AuthIdentity> signIn({
    required String email,
    required String password,
  });

  Future<void> signOut();

  Future<void> sendEmailVerification();

  /// Re-reads the user record so a freshly clicked verification link is seen.
  Future<AuthIdentity> reloadIdentity();

  Future<void> sendPasswordReset(String email);

  Future<UserModel?> fetchProfile(String uid);

  Future<void> saveProfile(UserModel user);
}

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  @override
  AuthIdentity? get currentIdentity {
    final user = _auth.currentUser;
    return user == null ? null : _toIdentity(user);
  }

  @override
  Stream<AuthIdentity?> authStateChanges() {
    return _auth.authStateChanges().map((user) {
      return user == null ? null : _toIdentity(user);
    });
  }

  @override
  Future<AuthIdentity> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user == null) {
      throw StateError('Account creation returned no user.');
    }

    final name =
        displayName.trim().isEmpty ? 'Swipeinn user' : displayName.trim();
    await user.updateDisplayName(name);

    // Verification is sent before any Firestore write so a network failure
    // never strands an account that cannot be verified. The profile document
    // is created by the auth gate once the address is confirmed.
    await user.sendEmailVerification();

    return _toIdentity(user);
  }

  @override
  Future<AuthIdentity> signIn({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user == null) throw StateError('Sign-in returned no user.');
    return _toIdentity(user);
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('No signed-in user to verify.');
    await user.sendEmailVerification();
  }

  @override
  Future<AuthIdentity> reloadIdentity() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('No signed-in user to reload.');
    await user.reload();
    final refreshed = _auth.currentUser;
    if (refreshed == null) throw StateError('Session ended while reloading.');
    return _toIdentity(refreshed);
  }

  @override
  Future<void> sendPasswordReset(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  @override
  Future<UserModel?> fetchProfile(String uid) async {
    final snapshot = await _db.collection('users').doc(uid).get();
    final data = snapshot.data();
    if (data == null) return null;
    return UserModel.fromMap(data, uid);
  }

  @override
  Future<void> saveProfile(UserModel user) async {
    final map = user.toMap();
    map['updatedAt'] = FieldValue.serverTimestamp();
    await _db.collection('users').doc(user.uid).set(map, SetOptions(merge: true));
  }

  static AuthIdentity _toIdentity(User user) {
    return AuthIdentity(
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName ?? '',
      isEmailVerified: user.emailVerified,
    );
  }
}
