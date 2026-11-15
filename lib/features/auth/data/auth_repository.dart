import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../../../core/services/database_service.dart';
import '../domain/auth_state.dart';
import '../domain/user_model.dart';

/// The default backend. Tests override this provider with an in-memory
/// implementation so the suite never needs a live Supabase project.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return SupabaseAuthRepository();
});

/// Everything the app needs from the identity provider and the profile store.
abstract class AuthRepository {
  /// Emits on every Supabase session change, including token refreshes that
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

  /// Renames the account in Supabase Auth and mirrors the new name onto the
  /// profile row.
  Future<void> updateDisplayName(String displayName);
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseClient get _client => Supabase.instance.client;

  @override
  AuthIdentity? get currentIdentity {
    final user = _client.auth.currentUser;
    return user == null ? null : _toIdentity(user);
  }

  @override
  Stream<AuthIdentity?> authStateChanges() {
    return _client.auth.onAuthStateChange.map((change) {
      final user = change.session?.user;
      return user == null ? null : _toIdentity(user);
    });
  }

  @override
  Future<AuthIdentity> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final name =
        displayName.trim().isEmpty ? 'Swipeinn user' : displayName.trim();

    // "Confirm email" is disabled for this project, so Supabase marks the
    // address confirmed at creation and returns a live session. The display
    // name rides along in user metadata instead of costing a second request.
    final response = await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'display_name': name},
    );

    final user = response.user;
    if (user == null) {
      throw StateError('Account creation returned no user.');
    }

    // The profile row is created by the auth gate once the identity reaches
    // `ready`; writing it here would race that first read.
    return _toIdentity(user);
  }

  @override
  Future<AuthIdentity> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    final user = response.user;
    if (user == null) throw StateError('Sign-in returned no user.');
    return _toIdentity(user);
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<void> sendEmailVerification() async {
    final email = _client.auth.currentUser?.email;
    if (email == null) throw StateError('No signed-in user to verify.');
    await _client.auth.resend(type: OtpType.signup, email: email);
  }

  @override
  Future<AuthIdentity> reloadIdentity() async {
    if (_client.auth.currentSession == null) {
      throw StateError('No signed-in user to reload.');
    }

    // refreshSession re-reads the user record; emailConfirmedAt is what the
    // gate watches, so a stale cached user would pin the account to the
    // verification screen forever.
    final response = await _client.auth.refreshSession();
    final user = response.user ?? _client.auth.currentUser;
    if (user == null) throw StateError('Session ended while reloading.');

    return _toIdentity(user);
  }

  @override
  Future<void> sendPasswordReset(String email) {
    return _client.auth.resetPasswordForEmail(email.trim());
  }

  @override
  Future<UserModel?> fetchProfile(String uid) async {
    // Through DatabaseService rather than a raw query so a cold start without
    // a connection can still restore the last profile from the local mirror.
    final data = await DatabaseService.instance
        .getDocument(collection: 'users', docId: uid);
    if (data == null) return null;
    return UserModel.fromMap(Map<String, dynamic>.from(data), uid);
  }

  @override
  Future<void> saveProfile(UserModel user) async {
    final map = Map<String, dynamic>.from(user.toMap());
    map['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    // Merge, not replace: the caller may only be changing a subset of fields,
    // and DatabaseService turns this into an UPDATE with an INSERT fallback.
    await DatabaseService.instance.setDocument(
      collection: 'users',
      docId: user.uid,
      data: map,
    );
  }

  @override
  Future<void> updateDisplayName(String displayName) async {
    final name = displayName.trim();
    if (name.isEmpty) {
      throw ArgumentError.value(displayName, 'displayName', 'Cannot be empty');
    }
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('No signed-in user to rename.');

    await _client.auth.updateUser(
      UserAttributes(data: {'display_name': name}),
    );

    final profile = await fetchProfile(user.id);
    if (profile != null) {
      await saveProfile(profile.copyWith(displayName: name));
    }
  }

  static AuthIdentity _toIdentity(User user) {
    final metadata = user.userMetadata;
    final displayName = metadata?['display_name'];
    return AuthIdentity(
      uid: user.id,
      email: user.email ?? '',
      displayName: displayName is String ? displayName : '',
      isEmailVerified: user.emailConfirmedAt != null,
    );
  }
}
