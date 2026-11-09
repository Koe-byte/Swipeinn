import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../domain/user_model.dart';
import '../data/auth_repository.dart';

export '../data/auth_repository.dart' show authDatabaseRepositoryProvider, AuthDatabaseRepository;

// Current active authenticated user state
final authStateProvider = StateNotifierProvider<AuthNotifier, AsyncValue<UserModel?>>((ref) {
  final repo = ref.watch(authDatabaseRepositoryProvider);
  return AuthNotifier(repo);
});

class AuthNotifier extends StateNotifier<AsyncValue<UserModel?>> {
  final AuthDatabaseRepository _repo;

  AuthNotifier(this._repo) : super(const AsyncValue.data(null));

  // Quick Mock or Firebase sign-in for testing & dev
  Future<void> signInWithRole({
    required String email,
    required String displayName,
    required UserRole role,
  }) async {
    state = const AsyncValue.loading();
    try {
      // Automatic Verification for educational domains (e.g. .edu)
      final isCampusEmail = email.toLowerCase().endsWith('.edu') ||
          email.toLowerCase().contains('.edu.');

      final defaultUid = role == UserRole.student ? 'student_sample_1' : 'landlord_101';
      final isSampleEmail = email == 'student@ust.edu.ph' ||
          email == 'maria.santos@ust.edu.ph' ||
          email == 'host@rently.ph';
      String uid = isSampleEmail
          ? defaultUid
          : (email.isNotEmpty
              ? 'user_${email.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}'
              : defaultUid);

      final auth = _repo.firebaseAuth;
      if (auth != null) {
        try {
          if (auth.currentUser == null) {
            final cred = await auth.signInAnonymously().timeout(const Duration(seconds: 2));
            if (cred.user != null) {
              uid = cred.user!.uid;
            }
          } else {
            uid = auth.currentUser!.uid;
          }
        } catch (e) {
          debugPrint('[Auth] Session initialization note: $e');
        }
      }

      // Check if user already exists in database
      final existingProfile = await _repo.fetchUserProfile(uid);
      if (existingProfile != null) {
        state = AsyncValue.data(existingProfile);
        return;
      }

      final user = UserModel(
        uid: uid,
        email: email,
        displayName: displayName,
        role: role,
        isVerified: isCampusEmail || role == UserRole.landlord,
        school: isCampusEmail ? 'University of Santo Tomas' : 'State College',
        photoUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=400&q=80',
        hasCompletedOnboarding: role != UserRole.student,
        lifestyleTags: ['Non-Smoker', 'Quiet Hours', 'Night Owl'],
      );

      // Immediate state update ensures zero UI freeze on login
      state = AsyncValue.data(user);
      _repo.saveUserProfile(user).catchError((e) {
        debugPrint('[Auth] Background profile save notice: $e');
      });
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  // Google OAuth sign-in
  Future<void> signInWithGoogle({required UserRole role}) async {
    state = const AsyncValue.loading();
    try {
      final isStudent = role == UserRole.student;
      String uid = isStudent ? 'student_google_demo' : 'landlord_google_demo';
      String email = isStudent ? 'alex.cruz@ust.edu.ph' : 'host.manila@gmail.com';
      String displayName = isStudent ? 'Alex Cruz' : 'Manila Dorms Host';
      String photoUrl = isStudent
          ? 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=400&q=80'
          : 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=400&q=80';

      final auth = _repo.firebaseAuth;
      if (auth != null) {
        try {
          final googleProvider = GoogleAuthProvider();
          googleProvider.addScope('email');
          googleProvider.addScope('profile');
          UserCredential credential;
          if (kIsWeb) {
            credential = await auth.signInWithPopup(googleProvider);
          } else {
            credential = await auth.signInWithProvider(googleProvider);
          }
          final fbUser = credential.user;
          if (fbUser != null) {
            uid = fbUser.uid;
            email = fbUser.email ?? email;
            displayName = fbUser.displayName ?? displayName;
            photoUrl = fbUser.photoURL ?? photoUrl;
          } else {
            state = const AsyncValue.data(null);
            return;
          }
        } on FirebaseAuthException catch (e) {
          debugPrint('[Auth] FirebaseAuth Google error: ${e.code} - ${e.message}');
          state = const AsyncValue.data(null);
          return;
        } catch (e) {
          debugPrint('[Auth] Google Sign-In notice: $e');
          state = const AsyncValue.data(null);
          return;
        }
      }

      // Check if user already exists in database
      final existingProfile = await _repo.fetchUserProfile(uid);
      if (existingProfile != null) {
        state = AsyncValue.data(existingProfile);
        return;
      }

      final isCampusEmail = email.toLowerCase().endsWith('.edu') ||
          email.toLowerCase().contains('.edu.');

      final user = UserModel(
        uid: uid,
        email: email,
        displayName: displayName,
        role: role,
        isVerified: isCampusEmail || role == UserRole.landlord,
        school: isCampusEmail ? 'University of Santo Tomas' : (isStudent ? 'State University' : ''),
        photoUrl: photoUrl,
        authProvider: 'google',
        hasCompletedOnboarding: !isStudent,
        lifestyleTags: isStudent ? ['Quiet Hours', 'Non-Smoker'] : [],
      );
      state = AsyncValue.data(user);
      _repo.saveUserProfile(user).catchError((e) {
        debugPrint('[Auth] Background profile save notice: $e');
      });
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  // Facebook OAuth sign-in
  Future<void> signInWithFacebook({required UserRole role}) async {
    state = const AsyncValue.loading();
    try {
      final isStudent = role == UserRole.student;
      String uid = isStudent ? 'student_fb_demo' : 'landlord_fb_demo';
      String email = isStudent ? 'maria.santos@gmail.com' : 'heritage.rentals@facebook.com';
      String displayName = isStudent ? 'Maria Santos' : 'Heritage Living Co.';
      String photoUrl = isStudent
          ? 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=400&q=80'
          : 'https://images.unsplash.com/photo-1560250097-0b93528c311a?auto=format&fit=crop&w=400&q=80';

      final auth = _repo.firebaseAuth;
      if (auth != null) {
        try {
          final fbProvider = FacebookAuthProvider();
          fbProvider.addScope('email');
          fbProvider.addScope('public_profile');
          UserCredential credential;
          if (kIsWeb) {
            credential = await auth.signInWithPopup(fbProvider);
          } else {
            credential = await auth.signInWithProvider(fbProvider);
          }
          final fbUser = credential.user;
          if (fbUser != null) {
            uid = fbUser.uid;
            email = fbUser.email ?? email;
            displayName = fbUser.displayName ?? displayName;
            photoUrl = fbUser.photoURL ?? photoUrl;
          } else {
            state = const AsyncValue.data(null);
            return;
          }
        } on FirebaseAuthException catch (e) {
          debugPrint('[Auth] FirebaseAuth Facebook error: ${e.code} - ${e.message}');
          state = const AsyncValue.data(null);
          return;
        } catch (e) {
          debugPrint('[Auth] Facebook Sign-In notice: $e');
          state = const AsyncValue.data(null);
          return;
        }
      }

      // Check if user already exists in database
      final existingProfile = await _repo.fetchUserProfile(uid);
      if (existingProfile != null) {
        state = AsyncValue.data(existingProfile);
        return;
      }

      final isCampusEmail = email.toLowerCase().endsWith('.edu') ||
          email.toLowerCase().contains('.edu.');

      final user = UserModel(
        uid: uid,
        email: email,
        displayName: displayName,
        role: role,
        isVerified: isCampusEmail || role == UserRole.landlord,
        school: isCampusEmail ? 'DLSU Manila' : (isStudent ? 'State University' : ''),
        photoUrl: photoUrl,
        authProvider: 'facebook',
        hasCompletedOnboarding: !isStudent,
        lifestyleTags: isStudent ? ['Clean & Organized', 'Visitors Allowed'] : [],
      );
      state = AsyncValue.data(user);
      _repo.saveUserProfile(user).catchError((e) {
        debugPrint('[Auth] Background profile save notice: $e');
      });
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  // Complete demographic onboarding
  void completeStudentDemographics(StudentDemographics demographics) {
    state.whenData((currentUser) {
      if (currentUser != null) {
        final combinedLifestyle = {
          ...currentUser.lifestyleTags,
          ...demographics.houseRules,
        }.toList();

        final updated = currentUser.copyWith(
          demographics: demographics,
          hasCompletedOnboarding: true,
          lifestyleTags: combinedLifestyle,
        );
        _repo.saveUserProfile(updated);
        state = AsyncValue.data(updated);
      }
    });
  }

  // Skip demographic onboarding
  void skipStudentDemographics() {
    state.whenData((currentUser) {
      if (currentUser != null) {
        final updated = currentUser.copyWith(
          hasCompletedOnboarding: true,
        );
        _repo.saveUserProfile(updated);
        state = AsyncValue.data(updated);
      }
    });
  }

  Future<void> signOut() async {
    try {
      await _repo.firebaseAuth?.signOut();
    } catch (e) {
      debugPrint('[Auth] Sign-out notice: $e');
    }
    state = const AsyncValue.data(null);
  }

  void switchRole(UserRole newRole) {
    state.whenData((currentUser) {
      if (currentUser != null) {
        final newUid = newRole == UserRole.student ? 'student_sample_1' : 'landlord_101';
        final updated = currentUser.copyWith(
          role: newRole,
          uid: currentUser.uid.startsWith('student_') || currentUser.uid.startsWith('landlord_') || currentUser.uid.startsWith('user_')
              ? newUid
              : currentUser.uid,
        );
        _repo.saveUserProfile(updated);
        state = AsyncValue.data(updated);
      }
    });
  }
}
