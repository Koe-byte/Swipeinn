import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Maps Firebase Auth failures to copy a person can act on.
String authErrorMessage(Object? error) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'email-already-in-use':
        return 'That email is already registered. Sign in instead.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'weak-password':
        return 'Use at least 6 characters for your password.';
      case 'wrong-password':
      case 'invalid-credential':
      case 'user-not-found':
        return 'Incorrect email or password.';
      case 'too-many-requests':
        return 'Too many attempts. Wait a minute and try again.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      case 'operation-not-allowed':
        return 'Email sign-in is disabled for this project. Enable Email/Password under Authentication > Sign-in method.';
      case 'unauthorized-domain':
        return 'This domain is not authorized. Add it under Authentication > Settings > Authorized domains.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'requires-recent-login':
        return 'Sign in again before making this change.';
      default:
        return error.message ?? 'Authentication failed (${error.code}).';
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
    // A restored Firebase session is available synchronously; applying it now
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

  Future<void> resendVerificationEmail() async {
    state =
        state.copyWith(isSubmitting: true, clearError: true, clearInfo: true);
    try {
      await _repo.sendEmailVerification();
      state = state.copyWith(
        isSubmitting: false,
        infoMessage:
            'Verification email sent. Check your inbox and spam folder.',
      );
    } catch (error) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: authErrorMessage(error),
      );
    }
  }

  /// Called when the person returns from their inbox. Firebase caches the
  /// user record, so a reload is required to see the updated flag.
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
