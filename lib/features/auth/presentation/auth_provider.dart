import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../domain/user_model.dart';

export '../data/auth_repository.dart' show authDatabaseRepositoryProvider, AuthDatabaseRepository;

// Current active authenticated user state.
final authStateProvider = StateNotifierProvider<AuthNotifier, AsyncValue<UserModel?>>((ref) {
  final repo = ref.watch(authDatabaseRepositoryProvider);
  return AuthNotifier(repo);
});

/// Thrown when Firebase Auth has a valid user but no Rently profile document.
/// The auth gate turns this into the "complete your profile" screen.
class ProfileSetupRequired implements Exception {
  final String uid;
  final String email;
  final String displayName;

  const ProfileSetupRequired({
    required this.uid,
    required this.email,
    required this.displayName,
  });

  @override
  String toString() => 'Profile setup required for $email';
}

/// Thrown when a fixed demo account exists but the shared demo password does
/// not work (for example, the account was created manually with a different
/// password or is linked to another provider).
class DemoAccountSetupRequired implements Exception {
  final String email;
  final String password;

  const DemoAccountSetupRequired({
    required this.email,
    this.password = 'RentlyDemo123!',
  });

  String get message =>
      'The demo account $email exists with a different password. Reset it to '
      '"$password" in Firebase Console > Authentication > Users, or delete '
      'the account and try again.';

  @override
  String toString() => message;
}

/// Maps Firebase Auth failures to user-facing copy.
String authErrorMessage(Object? error) {
  if (error is ProfileSetupRequired) {
    return 'Finish setting up your profile to continue.';
  }
  if (error is DemoAccountSetupRequired) {
    return error.message;
  }
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'email-already-in-use':
        return 'That email is already registered. Try signing in instead.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'weak-password':
        return 'Use a stronger password (at least 6 characters).';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'user-not-found':
        return 'No account found for that email.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'operation-not-allowed':
        return 'This sign-in method is disabled in Firebase. Enable it under Authentication > Sign-in method.';
      case 'unauthorized-domain':
        return 'This domain is not authorized for OAuth. Add it under Authentication > Settings > Authorized domains.';
      case 'account-exists-with-different-credential':
        return 'This email is linked to a different sign-in method.';
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
      case 'web-context-cancelled':
        return 'Sign-in was cancelled. No changes were made.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      case 'user-disabled':
        return 'This account has been disabled. Contact support.';
      default:
        return error.message ?? 'Authentication failed (${error.code}).';
    }
  }
  if (error is StateError) return error.message.toString();
  return 'Something went wrong. Please try again.';
}

class AuthNotifier extends StateNotifier<AsyncValue<UserModel?>> {
  final AuthDatabaseRepository _repo;

  StreamSubscription<User?>? _authSubscription;
  bool _manualAuthInProgress = false;
  bool _initialRestoreComplete = false;

  AuthNotifier(this._repo) : super(const AsyncValue.loading()) {
    _init();
  }

  /// True once the persisted Firebase session has been checked (or when
  /// running without Firebase). The auth gate only shows the splash while
  /// this is false; manual sign-in loading must not flash the splash.
  bool get isInitialRestoreComplete => _initialRestoreComplete;

  void _init() {
    final auth = _repo.firebaseAuth;
    if (auth == null) {
      // Local/demo mode: no persisted Firebase session to restore.
      _initialRestoreComplete = true;
      state = const AsyncValue.data(null);
      return;
    }

    _authSubscription = auth.authStateChanges().listen(
      _handleAuthStateChange,
      onError: (Object e, StackTrace st) {
        debugPrint('[Auth] authStateChanges error: $e');
        _initialRestoreComplete = true;
        if (state.isLoading) state = const AsyncValue.data(null);
      },
    );
  }

  Future<void> _handleAuthStateChange(User? fbUser) async {
    _initialRestoreComplete = true;
    if (_manualAuthInProgress) return;

    if (fbUser == null) {
      state = const AsyncValue.data(null);
      return;
    }

    final current = state.valueOrNull;
    if (current != null && current.uid == fbUser.uid) return;

    try {
      final profile = await _repo.fetchUserProfile(fbUser.uid);
      if (profile != null) {
        state = AsyncValue.data(profile);
        // Repair accounts whose profile exists only in the local cache.
        unawaited(_repo.ensureProfileInCloud(profile));
      } else {
        state = AsyncValue.error(
          ProfileSetupRequired(
            uid: fbUser.uid,
            email: fbUser.email ?? '',
            displayName: fbUser.displayName ?? '',
          ),
          StackTrace.current,
        );
      }
    } catch (e, st) {
      debugPrint('[Auth] Profile restore failed: $e');
      state = AsyncValue.error(e, st);
    }
  }

  // ---------------------------------------------------------------------------
  // Email / password
  // ---------------------------------------------------------------------------

  Future<void> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
    required UserRole role,
  }) async {
    final auth = _repo.firebaseAuth;
    if (auth == null) {
      await _signInMock(
        email: email,
        displayName: displayName,
        role: role,
        authProvider: 'email',
      );
      return;
    }

    _manualAuthInProgress = true;
    state = const AsyncValue.loading();
    try {
      final credential = await auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final fbUser = credential.user;
      if (fbUser == null) throw StateError('Account creation returned no user.');

      final name = displayName.trim().isEmpty ? 'Rently User' : displayName.trim();
      await fbUser.updateDisplayName(name);

      final profile = _buildProfile(
        uid: fbUser.uid,
        email: fbUser.email ?? email.trim(),
        displayName: name,
        role: role,
        authProvider: 'email',
      );
      await _repo.saveUserProfile(profile);
      state = AsyncValue.data(profile);
    } on FirebaseAuthException catch (e, st) {
      state = AsyncValue.error(e, st);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    } finally {
      _manualAuthInProgress = false;
    }
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final auth = _repo.firebaseAuth;
    if (auth == null) {
      state = AsyncValue.error(
        StateError('Email sign-in needs Firebase. Use a demo account in local mode.'),
        StackTrace.current,
      );
      return;
    }

    _manualAuthInProgress = true;
    state = const AsyncValue.loading();
    try {
      final credential = await auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final fbUser = credential.user;
      if (fbUser == null) throw StateError('Sign-in returned no user.');

      final profile = await _repo.fetchUserProfile(fbUser.uid);
      if (profile == null) {
        state = AsyncValue.error(
          ProfileSetupRequired(
            uid: fbUser.uid,
            email: fbUser.email ?? email.trim(),
            displayName: fbUser.displayName ?? '',
          ),
          StackTrace.current,
        );
        return;
      }
      state = AsyncValue.data(profile);
      // If the profile was recovered from the local cache, re-upload it so
      // `users/{uid}` exists in Firestore for the next session.
      unawaited(_repo.ensureProfileInCloud(profile));
    } on FirebaseAuthException catch (e, st) {
      state = AsyncValue.error(e, st);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    } finally {
      _manualAuthInProgress = false;
    }
  }

  // ---------------------------------------------------------------------------
  // OAuth
  // ---------------------------------------------------------------------------

  Future<void> signInWithGoogle({
    UserRole? role,
    bool createProfileIfMissing = false,
  }) async {
    final auth = _repo.firebaseAuth;
    if (auth == null) {
      final effectiveRole = role ?? UserRole.student;
      await _signInMock(
        email: effectiveRole == UserRole.student ? 'alex.cruz@ust.edu.ph' : 'host.manila@gmail.com',
        displayName: effectiveRole == UserRole.student ? 'Alex Cruz' : 'Manila Dorms Host',
        role: effectiveRole,
        authProvider: 'google',
        uidOverride: effectiveRole == UserRole.student ? 'student_google_demo' : 'landlord_google_demo',
        photoUrl: effectiveRole == UserRole.student
            ? 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=400&q=80'
            : 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=400&q=80',
      );
      return;
    }

    _manualAuthInProgress = true;
    state = const AsyncValue.loading();
    try {
      final googleProvider = GoogleAuthProvider();
      googleProvider.addScope('email');
      googleProvider.addScope('profile');
      final credential = kIsWeb
          ? await auth.signInWithPopup(googleProvider)
          : await auth.signInWithProvider(googleProvider);
      await _finishOAuth(
        credential,
        providerName: 'google',
        role: role,
        createProfileIfMissing: createProfileIfMissing,
      );
    } on FirebaseAuthException catch (e, st) {
      state = AsyncValue.error(e, st);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    } finally {
      _manualAuthInProgress = false;
    }
  }

  Future<void> signInWithFacebook({
    UserRole? role,
    bool createProfileIfMissing = false,
  }) async {
    final auth = _repo.firebaseAuth;
    if (auth == null) {
      final effectiveRole = role ?? UserRole.student;
      await _signInMock(
        email: effectiveRole == UserRole.student ? 'maria.santos@gmail.com' : 'heritage.rentals@facebook.com',
        displayName: effectiveRole == UserRole.student ? 'Maria Santos' : 'Heritage Living Co.',
        role: effectiveRole,
        authProvider: 'facebook',
        uidOverride: effectiveRole == UserRole.student ? 'student_fb_demo' : 'landlord_fb_demo',
        photoUrl: effectiveRole == UserRole.student
            ? 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=400&q=80'
            : 'https://images.unsplash.com/photo-1560250097-0b93528c311a?auto=format&fit=crop&w=400&q=80',
      );
      return;
    }

    _manualAuthInProgress = true;
    state = const AsyncValue.loading();
    try {
      final fbProvider = FacebookAuthProvider();
      // Only request public_profile. Requesting 'email' triggers
      // "Invalid Scopes: email" unless the Meta app has that permission
      // approved, which blocks local testing entirely.
      fbProvider.addScope('public_profile');
      final credential = kIsWeb
          ? await auth.signInWithPopup(fbProvider)
          : await auth.signInWithProvider(fbProvider);
      await _finishOAuth(
        credential,
        providerName: 'facebook',
        role: role,
        createProfileIfMissing: createProfileIfMissing,
      );
    } on FirebaseAuthException catch (e, st) {
      debugPrint('[Auth] Facebook Sign-In failed (${e.code} - ${e.message}).');
      // Never substitute a mock identity when Firebase Auth is configured.
      // Cancellation and provider errors are surfaced to the user instead.
      state = AsyncValue.error(e, st);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    } finally {
      _manualAuthInProgress = false;
    }
  }

  Future<void> _finishOAuth(
    UserCredential credential, {
    required String providerName,
    required UserRole? role,
    required bool createProfileIfMissing,
  }) async {
    final fbUser = credential.user;
    if (fbUser == null) throw StateError('OAuth sign-in returned no user.');

    final existing = await _repo.fetchUserProfile(fbUser.uid);
    if (existing != null) {
      state = AsyncValue.data(existing);
      unawaited(_repo.ensureProfileInCloud(existing));
      return;
    }

    if (!createProfileIfMissing || role == null) {
      state = AsyncValue.error(
        ProfileSetupRequired(
          uid: fbUser.uid,
          email: fbUser.email ?? '',
          displayName: fbUser.displayName ?? '',
        ),
        StackTrace.current,
      );
      return;
    }

    final profile = _buildProfile(
      uid: fbUser.uid,
      email: fbUser.email ?? '',
      displayName: fbUser.displayName ?? 'Rently User',
      role: role,
      authProvider: providerName,
      photoUrl: fbUser.photoURL ?? '',
    );
    await _repo.saveUserProfile(profile);
    state = AsyncValue.data(profile);
  }

  /// Completes a missing profile for an already-authenticated Firebase user
  /// (legacy account or first-time OAuth sign-in from the sign-in screen).
  Future<void> completeProfile({
    required UserRole role,
    String? displayName,
  }) async {
    final pending = state.hasError && state.error is ProfileSetupRequired
        ? state.error as ProfileSetupRequired
        : null;
    if (pending == null) return;

    state = const AsyncValue.loading();
    try {
      final name = (displayName ?? pending.displayName).trim();
      final fbUser = _repo.firebaseAuth?.currentUser;
      var provider = 'email';
      for (final info in fbUser?.providerData ?? const []) {
        if (info.providerId == 'google.com') {
          provider = 'google';
          break;
        }
        if (info.providerId == 'facebook.com') {
          provider = 'facebook';
          break;
        }
      }
      final profile = _buildProfile(
        uid: pending.uid,
        email: pending.email.isEmpty ? (fbUser?.email ?? '') : pending.email,
        displayName: name.isEmpty ? 'Rently User' : name,
        role: role,
        authProvider: provider,
        photoUrl: fbUser?.photoURL ?? '',
      );
      await fbUser?.updateDisplayName(profile.displayName);
      await _repo.saveUserProfile(profile);
      state = AsyncValue.data(profile);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  // ---------------------------------------------------------------------------
  // Demo / mock identities
  // ---------------------------------------------------------------------------

  /// Debug/demo sign-in. Uses fixed Firebase demo accounts when Auth is
  /// configured, otherwise a local mock identity. Never uses anonymous auth.
  Future<void> signInAsDemo({
    required UserRole role,
    String? email,
    String? displayName,
  }) async {
    final auth = _repo.firebaseAuth;
    final fallbackEmail = email ??
        (role == UserRole.student ? 'student@ust.edu.ph' : 'host@rently.ph');
    final fallbackName = displayName ??
        (role == UserRole.student ? 'Alex Cruz' : 'Manila Dorms Host');

    if (auth == null) {
      await _signInMock(
        email: fallbackEmail,
        displayName: fallbackName,
        role: role,
      );
      return;
    }

    const demoPassword = 'RentlyDemo123!';
    final demoEmail =
        role == UserRole.student ? 'student.demo@rently.ph' : 'host.demo@rently.ph';
    final demoName = role == UserRole.student ? 'Alex Cruz' : 'Manila Dorms Host';

    _manualAuthInProgress = true;
    state = const AsyncValue.loading();
    try {
      UserCredential credential;
      try {
        credential = await auth.signInWithEmailAndPassword(
          email: demoEmail,
          password: demoPassword,
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
          try {
            credential = await auth.createUserWithEmailAndPassword(
              email: demoEmail,
              password: demoPassword,
            );
            await credential.user?.updateDisplayName(demoName);
          } on FirebaseAuthException catch (createError) {
            // The account exists but the shared password/provider does not
            // match. Recreating it is impossible, so surface a precise fix.
            if (createError.code == 'email-already-in-use') {
              throw DemoAccountSetupRequired(email: demoEmail);
            }
            rethrow;
          }
        } else {
          rethrow;
        }
      }

      final fbUser = credential.user;
      if (fbUser == null) throw StateError('Demo sign-in returned no user.');

      final existing = await _repo.fetchUserProfile(fbUser.uid);
      if (existing != null) {
        state = AsyncValue.data(existing);
        unawaited(_repo.ensureProfileInCloud(existing));
        return;
      }

      final profile = _buildProfile(
        uid: fbUser.uid,
        email: demoEmail,
        displayName: demoName,
        role: role,
        authProvider: 'email',
      );
      await _repo.saveUserProfile(profile);
      state = AsyncValue.data(profile);
    } on FirebaseAuthException catch (e, st) {
      debugPrint('[Auth] Demo sign-in failed (${e.code} - ${e.message}).');
      state = AsyncValue.error(e, st);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    } finally {
      _manualAuthInProgress = false;
    }
  }

  @Deprecated('Use signInAsDemo, signInWithEmail, or signUpWithEmail.')
  Future<void> signInWithRole({
    required String email,
    required String displayName,
    required UserRole role,
  }) {
    return signInAsDemo(role: role, email: email, displayName: displayName);
  }

  Future<void> _signInMock({
    required String email,
    required String displayName,
    required UserRole role,
    String authProvider = 'email',
    String? uidOverride,
    String? photoUrl,
  }) async {
    state = const AsyncValue.loading();
    try {
      final normalizedEmail = email.trim().toLowerCase();
      final isCampusEmail = normalizedEmail.endsWith('.edu') ||
          normalizedEmail.contains('.edu.');

      final defaultUid = role == UserRole.student ? 'student_sample_1' : 'landlord_101';
      final isSampleEmail = normalizedEmail == 'student@ust.edu.ph' ||
          normalizedEmail == 'maria.santos@ust.edu.ph' ||
          normalizedEmail == 'host@rently.ph';
      final uid = uidOverride ??
          (isSampleEmail
              ? defaultUid
              : (normalizedEmail.isNotEmpty
                  ? 'user_${normalizedEmail.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}'
                  : defaultUid));

      final existingProfile = await _repo.fetchLocalUserProfile(uid);
      if (existingProfile != null) {
        await _repo.cacheUserProfileLocally(existingProfile);
        state = AsyncValue.data(existingProfile);
        return;
      }

      final user = _buildProfile(
        uid: uid,
        email: email.trim(),
        displayName: displayName.trim().isEmpty ? 'Rently User' : displayName.trim(),
        role: role,
        authProvider: authProvider,
        photoUrl: photoUrl ?? '',
        school: isCampusEmail
            ? 'University of Santo Tomas'
            : (role == UserRole.student ? 'State College' : ''),
      );
      state = AsyncValue.data(user);
      // Mock identities are not Firebase Auth users, so they must never write
      // to Firestore. The durable local cache is their source of truth.
      await _repo.cacheUserProfileLocally(user);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  UserModel _buildProfile({
    required String uid,
    required String email,
    required String displayName,
    required UserRole role,
    String authProvider = 'email',
    String photoUrl = '',
    String? school,
  }) {
    final isCampusEmail = email.toLowerCase().endsWith('.edu') ||
        email.toLowerCase().contains('.edu.');
    final isStudent = role == UserRole.student;
    return UserModel(
      uid: uid,
      email: email,
      displayName: displayName,
      role: role,
      isVerified: isCampusEmail || role == UserRole.landlord,
      school: school ?? (isCampusEmail ? 'University of Santo Tomas' : ''),
      photoUrl: photoUrl.isEmpty
          ? (isStudent
              ? 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=400&q=80'
              : 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=400&q=80')
          : photoUrl,
      authProvider: authProvider,
      hasCompletedOnboarding: !isStudent,
      lifestyleTags: isStudent ? ['Non-Smoker', 'Quiet Hours', 'Night Owl'] : [],
    );
  }

  // ---------------------------------------------------------------------------
  // Onboarding
  // ---------------------------------------------------------------------------

  Future<void> completeStudentDemographics(StudentDemographics demographics) async {
    final currentUser = state.valueOrNull;
    if (currentUser == null) return;

    final combinedLifestyle = {
      ...currentUser.lifestyleTags,
      ...demographics.houseRules,
    }.toList();

    final updated = currentUser.copyWith(
      demographics: demographics,
      hasCompletedOnboarding: true,
      lifestyleTags: combinedLifestyle,
    );

    // Optimistic state update keeps the UI instant; persistence follows.
    state = AsyncValue.data(updated);
    try {
      await _repo.saveUserProfile(updated);
    } catch (e) {
      debugPrint('[Auth] Demographics save notice: $e');
    }
  }

  Future<void> skipStudentDemographics() async {
    final currentUser = state.valueOrNull;
    if (currentUser == null) return;

    final updated = currentUser.copyWith(hasCompletedOnboarding: true);
    state = AsyncValue.data(updated);
    try {
      await _repo.saveUserProfile(updated);
    } catch (e) {
      debugPrint('[Auth] Onboarding skip save notice: $e');
    }
  }

  /// Clears a failed sign-in/sign-up error when the user navigates between
  /// auth screens. `ProfileSetupRequired` is preserved so the auth gate can
  /// still route to the profile-completion step.
  void clearAuthError() {
    if (state.hasError && state.error is! ProfileSetupRequired) {
      state = const AsyncValue.data(null);
    }
  }

  Future<void> signOut() async {
    try {
      await _repo.firebaseAuth?.signOut();
    } catch (e) {
      debugPrint('[Auth] Sign-out notice: $e');
    }
    state = const AsyncValue.data(null);
  }

  // ---------------------------------------------------------------------------
  // Dev-only role switching (never exposed in production chat/profile flows)
  // ---------------------------------------------------------------------------

  bool _roleSwitchAllowedDuringOnboarding = false;

  void setRoleSwitchAllowedDuringOnboarding(bool allowed) {
    _roleSwitchAllowedDuringOnboarding = allowed;
  }

  bool get _canSwitchRole => kDebugMode || _roleSwitchAllowedDuringOnboarding;

  void switchRole(UserRole newRole) {
    if (!_canSwitchRole) {
      debugPrint(
        '[Auth] switchRole ignored: role switching is only available in debug '
        'or onboarding flows (requested role: ${newRole.name}).',
      );
      return;
    }

    final currentUser = state.valueOrNull;
    if (currentUser == null) return;

    final updated = currentUser.copyWith(role: newRole);
    state = AsyncValue.data(updated);
    unawaited(_repo.saveUserProfile(updated).catchError((Object e) {
      debugPrint('[Auth] Role switch save notice: $e');
      return false;
    }));
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
