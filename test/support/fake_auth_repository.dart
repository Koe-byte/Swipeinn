import 'dart:async';
import 'dart:typed_data';

import 'package:swipeinn/features/auth/data/auth_repository.dart';
import 'package:swipeinn/features/auth/domain/auth_state.dart';
import 'package:swipeinn/features/auth/domain/user_model.dart';

/// In-memory stand-in for Supabase Auth. Keeps the suite offline and
/// deterministic.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({AuthIdentity? initialIdentity, UserModel? initialProfile})
      : _current = initialIdentity,
        profile = initialProfile;

  AuthIdentity? _current;
  UserModel? profile;
  final _controller = StreamController<AuthIdentity?>.broadcast();

  /// Sign-up errors that the real backend would raise.
  Object? signUpError;

  /// Verification state applied by [reloadIdentity].
  bool markVerifiedOnReload = false;

  /// When set, [fetchProfile] throws so the failure state can be exercised.
  Object? fetchProfileError;

  int profileSaves = 0;
  int verificationEmailsSent = 0;
  int passwordResetsSent = 0;
  int avatarsUploaded = 0;
  int avatarsRemoved = 0;

  /// Verification address recorded by the last [sendEmailVerification].
  String? lastVerificationEmail;

  @override
  AuthIdentity? get currentIdentity => _current;

  @override
  Stream<AuthIdentity?> authStateChanges() async* {
    yield _current;
    yield* _controller.stream;
  }

  void emit(AuthIdentity? identity) {
    _current = identity;
    _controller.add(identity);
  }

  @override
  Future<AuthIdentity> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final error = signUpError;
    if (error != null) throw error;

    final identity = AuthIdentity(
      uid: 'uid-${email.trim()}',
      email: email.trim(),
      displayName: displayName.trim(),
      isEmailVerified: false,
    );
    _current = identity;
    profile = UserModel(
      uid: identity.uid,
      email: identity.email,
      displayName: identity.displayName,
      createdAt: 1,
    );
    emit(identity);
    return identity;
  }

  @override
  Future<AuthIdentity> signIn({
    required String email,
    required String password,
  }) async {
    final identity = AuthIdentity(
      uid: profile?.uid ?? 'uid-${email.trim()}',
      email: email.trim(),
      displayName: profile?.displayName ?? '',
      isEmailVerified: true,
    );
    emit(identity);
    return identity;
  }

  @override
  Future<AuthIdentity> reloadIdentity() async {
    final current = _current;
    if (current == null) throw StateError('No signed-in user to reload.');
    final refreshed = AuthIdentity(
      uid: current.uid,
      email: current.email,
      displayName: current.displayName,
      isEmailVerified: markVerifiedOnReload || current.isEmailVerified,
    );
    _current = refreshed;
    return refreshed;
  }

  @override
  Future<void> sendEmailVerification({String? email}) async {
    verificationEmailsSent++;
    lastVerificationEmail = email ?? _current?.email;
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    passwordResetsSent++;
  }

  @override
  Future<void> signOut() async {
    _current = null;
    emit(null);
  }

  @override
  Future<UserModel?> fetchProfile(String uid) async {
    final error = fetchProfileError;
    if (error != null) throw error;
    return profile?.uid == uid ? profile : null;
  }

  @override
  Future<void> saveProfile(UserModel user) async {
    profileSaves++;
    profile = user;
  }

  @override
  Future<UserModel> updateProfilePhoto({
    required UserModel user,
    required Uint8List bytes,
    required String fileName,
  }) async {
    avatarsUploaded++;
    final updated = user.copyWith(
      photoUrl: 'https://fake.test/avatars/${user.uid}/$fileName',
    );
    profile = updated;
    return updated;
  }

  @override
  Future<UserModel> clearProfilePhoto(UserModel user) async {
    avatarsRemoved++;
    final updated = user.copyWith(photoUrl: '');
    profile = updated;
    return updated;
  }

  @override
  Future<void> updateDisplayName(String displayName) async {
    final current = profile;
    if (current == null) throw StateError('No signed-in user to rename.');

    final name = displayName.trim();
    profile = current.copyWith(displayName: name);

    final identity = _current;
    if (identity != null) {
      _current = AuthIdentity(
        uid: identity.uid,
        email: identity.email,
        displayName: name,
        isEmailVerified: identity.isEmailVerified,
      );
    }
  }

  void dispose() {
    _controller.close();
  }
}
