import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/photo_storage_service.dart';
import '../data/auth_repository.dart';
import '../domain/auth_state.dart';
import '../domain/user_model.dart';

export '../data/auth_repository.dart'
    show authRepositoryProvider, AuthRepository;
export '../domain/auth_state.dart' show AuthState, AuthStatus, AuthIdentity;

/// The single source of truth for "who is signed in and how far through
/// onboarding they are".
final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.watch(authRepositoryProvider));
});

/// Maps Supabase Auth failures to copy a person can act on.
String authErrorMessage(Object? error) {
  // Must be tested before AuthException: it is a subclass, and a dropped
  // connection is the one failure people can actually do something about.
  if (error is AuthRetryableFetchException) {
    return 'Network error. Check your connection and try again.';
  }
  if (error is AuthException) {
    switch (error.code) {
      case 'user_already_exists':
      case 'email_exists':
        return 'That email is already registered. Sign in instead.';
      case 'email_address_invalid':
      case 'validation_failed':
        return 'Enter a valid email address.';
      case 'weak_password':
        return 'Use at least 6 characters for your password.';
      case 'invalid_credentials':
        return 'Incorrect email or password.';
      case 'email_not_confirmed':
        return 'Confirm your email address before signing in.';
      case 'over_email_send_rate_limit':
      case 'over_request_rate_limit':
        return 'Too many attempts. Wait a minute and try again.';
      case 'email_provider_disabled':
      case 'signup_disabled':
        return 'Email sign-in is disabled for this project. Enable the Email provider under Authentication > Providers.';
      case 'same_password':
        return 'Pick a password you have not used before.';
      case 'session_not_found':
      case 'refresh_token_not_found':
        return 'Your session expired. Sign in again.';
      default:
        final message = error.message.trim();
        if (message.isNotEmpty) return message;
        return 'Authentication failed (${error.code ?? 'unknown'}).';
    }
  }
  if (error is StateError) return error.message;
  return 'Something went wrong. Please try again.';
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repo;
  StreamSubscription<AuthIdentity?>? _subscription;

  /// Guards against an older profile read overwriting a newer one when the
  /// auth stream emits twice in quick succession.
  int _identityEpoch = 0;

  AuthNotifier(this._repo) : super(const AuthState()) {
    // A restored Supabase session is available synchronously; applying it now
    // avoids a splash flash on cold start. A null result still waits for the
    // stream so a slow restore never shows the signed-out screen by mistake.
    final restored = _repo.currentIdentity;
    if (restored != null) {
      unawaited(_applyIdentity(restored));
    }

    _subscription = _repo.authStateChanges().listen(
      (identity) => unawaited(_applyIdentity(identity)),
      onError: (Object error, StackTrace stack) {
        debugPrint('[Auth] authStateChanges error: $error');
        state = state.copyWith(
          status: AuthStatus.failure,
          errorMessage: authErrorMessage(error),
          isSubmitting: false,
        );
      },
    );
  }

  bool get isRestoring => state.status == AuthStatus.restoring;

  Future<void> _applyIdentity(AuthIdentity? identity) async {
    final epoch = ++_identityEpoch;

    if (identity == null) {
      state = const AuthState(status: AuthStatus.signedOut);
      return;
    }

    if (!identity.isEmailVerified) {
      state = AuthState(
        status: AuthStatus.unverified,
        email: identity.email,
        isEmailVerified: false,
        isSubmitting: false,
      );
      return;
    }

    try {
      var profile = await _repo.fetchProfile(identity.uid);
      final isNewProfile = profile == null;

      // A verified account with no document (interrupted sign-up, or a user
      // created directly in the console) gets one so they can finish
      // onboarding instead of hitting a dead end.
      profile ??= UserModel(
        uid: identity.uid,
        email: identity.email,
        displayName: identity.displayName.isEmpty
            ? 'Swipeinn user'
            : identity.displayName,
        authProvider: 'password',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      if (epoch != _identityEpoch) return;

      final needsOnboarding = !profile.hasCompletedOnboarding ||
          profile.preferences?.isComplete != true;

      if (needsOnboarding && profile.hasCompletedOnboarding) {
        profile = profile.copyWith(hasCompletedOnboarding: false);
      }

      // Only write when the document did not exist, so opening the app never
      // rewrites a profile that is already correct.
      if (isNewProfile) {
        await _repo.saveProfile(profile);
      }

      state = AuthState(
        status: needsOnboarding ? AuthStatus.needsOnboarding : AuthStatus.ready,
        user: profile,
        email: identity.email,
        isEmailVerified: true,
        isSubmitting: false,
      );
    } catch (error) {
      if (epoch != _identityEpoch) return;
      debugPrint('[Auth] Profile load failed: $error');
      state = AuthState(
        status: AuthStatus.failure,
        email: identity.email,
        errorMessage:
            'Could not load your profile. Check your connection and retry.',
        isSubmitting: false,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Email / password
  // ---------------------------------------------------------------------------

  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final identity = await _repo.signUp(
        email: email,
        password: password,
        displayName: displayName,
      );
      await _applyIdentity(identity);
    } catch (error) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: authErrorMessage(error),
      );
    }
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final identity = await _repo.signIn(email: email, password: password);
      await _applyIdentity(identity);
    } catch (error) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: authErrorMessage(error),
      );
    }
  }

  Future<bool> sendPasswordReset(String email) async {
    state =
        state.copyWith(isSubmitting: true, clearError: true, clearInfo: true);
    try {
      await _repo.sendPasswordReset(email);
      state = state.copyWith(
        isSubmitting: false,
        infoMessage: 'Password reset link sent to $email.',
      );
      return true;
    } catch (error) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: authErrorMessage(error),
      );
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Email verification
  // ---------------------------------------------------------------------------

  Future<bool> resendVerificationEmail() async {
    final email = state.email ?? state.user?.email;
    state =
        state.copyWith(isSubmitting: true, clearError: true, clearInfo: true);
    try {
      await _repo.sendEmailVerification(email: email);
      state = state.copyWith(
        isSubmitting: false,
        infoMessage:
            'Verification email sent. Check your inbox and spam folder.',
      );
      return true;
    } catch (error) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: authErrorMessage(error),
      );
      return false;
    }
  }

  /// Called when the person returns from their inbox. Supabase caches the
  /// user record, so a refresh is required to see the updated flag.
  Future<void> refreshVerification() async {
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final identity = await _repo.reloadIdentity();
      await _applyIdentity(identity);
    } catch (error) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: authErrorMessage(error),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Onboarding
  // ---------------------------------------------------------------------------

  Future<bool> completeOnboarding(RenterPreferences preferences) async {
    final current = state.user;
    if (current == null) return false;

    state = state.copyWith(isSubmitting: true, clearError: true);
    final updated = current.copyWith(
      preferences: preferences,
      hasCompletedOnboarding: true,
    );

    // Optimistic: the UI advances immediately, the write follows.
    state = state.copyWith(
      user: updated,
      status: AuthStatus.ready,
      isSubmitting: false,
    );

    try {
      await _repo.saveProfile(updated);
      return true;
    } catch (error) {
      debugPrint('[Auth] Preferences save failed: $error');
      state = state.copyWith(
        status: AuthStatus.needsOnboarding,
        user: current,
        errorMessage:
            'Could not save your preferences. Check your connection and try again.',
      );
      return false;
    }
  }

  /// Updates onboarding answers from the profile screen. Unlike
  /// [completeOnboarding] this never changes the gate status: the account was
  /// already ready.
  Future<bool> updatePreferences(RenterPreferences preferences) async {
    final current = state.user;
    if (current == null) return false;

    state = state.copyWith(isSubmitting: true, clearError: true);
    final updated = current.copyWith(
      preferences: preferences,
      hasCompletedOnboarding: true,
    );

    try {
      await _repo.saveProfile(updated);
      state = state.copyWith(
        user: updated,
        status: AuthStatus.ready,
        isSubmitting: false,
      );
      return true;
    } catch (error) {
      debugPrint('[Auth] Preferences update failed: $error');
      state = state.copyWith(
        isSubmitting: false,
        errorMessage:
            'Could not save your preferences. Check your connection and try again.',
      );
      return false;
    }
  }

  /// Renames the account. The UI updates immediately, then rolls back if the
  /// write fails so the profile never shows a name the backend did not accept.
  Future<bool> updateDisplayName(String displayName) async {
    final current = state.user;
    final name = displayName.trim();
    if (current == null || name.isEmpty) return false;
    if (name == current.displayName) return true;

    final updated = current.copyWith(displayName: name);
    state = state.copyWith(user: updated, clearError: true);

    try {
      await _repo.updateDisplayName(name);
      return true;
    } catch (error) {
      debugPrint('[Auth] Display name update failed: $error');
      state = state.copyWith(
        user: current,
        errorMessage:
            'Could not update your name. Check your connection and try again.',
      );
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Profile photo
  // ---------------------------------------------------------------------------

  /// Uploads a new avatar and mirrors its URL onto the profile.
  ///
  /// Returns `null` on success, or a sentence ready for a snackbar.
  Future<String?> updateProfilePhoto({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final current = state.user;
    if (current == null) return 'Sign in again to change your photo.';

    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final updated = await _repo.updateProfilePhoto(
        user: current,
        bytes: bytes,
        fileName: fileName,
      );
      state = state.copyWith(user: updated, isSubmitting: false);
      return null;
    } catch (error) {
      debugPrint('[Auth] Photo upload failed: $error');
      state = state.copyWith(isSubmitting: false);
      return _photoErrorMessage(error);
    }
  }

  /// Removes the stored avatar and falls back to the initial letter.
  Future<String?> removeProfilePhoto() async {
    final current = state.user;
    if (current == null) return 'Sign in again to change your photo.';

    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final updated = await _repo.clearProfilePhoto(current);
      state = state.copyWith(user: updated, isSubmitting: false);
      return null;
    } catch (error) {
      debugPrint('[Auth] Photo removal failed: $error');
      state = state.copyWith(isSubmitting: false);
      return 'Could not remove your photo. Check your connection and try again.';
    }
  }

  static String _photoErrorMessage(Object error) {
    if (error is PhotoUploadException) return error.message;
    return 'Could not update your photo. Check your connection and try again.';
  }

  // ---------------------------------------------------------------------------
  // Session
  // ---------------------------------------------------------------------------

  /// Re-attempts the profile load after a [AuthStatus.failure].
  Future<void> retry() async {
    final identity = _repo.currentIdentity;
    if (identity == null) {
      state = const AuthState(status: AuthStatus.signedOut);
      return;
    }
    state = state.copyWith(isSubmitting: true, clearError: true);
    await _applyIdentity(identity);
  }

  void clearError() {
    if (state.errorMessage != null || state.infoMessage != null) {
      state = state.copyWith(clearError: true, clearInfo: true);
    }
  }

  Future<void> signOut() async {
    try {
      await _repo.signOut();
    } catch (error) {
      debugPrint('[Auth] Sign-out notice: $error');
    }
    state = const AuthState(status: AuthStatus.signedOut);
  }

  /// Pushes an already-known identity through the gate. Used by tests and by
  /// the verification screen after a successful reload.
  @visibleForTesting
  Future<void> applyIdentityForTesting(AuthIdentity? identity) {
    return _applyIdentity(identity);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
