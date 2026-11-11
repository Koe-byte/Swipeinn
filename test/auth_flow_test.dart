import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rently/features/auth/domain/user_model.dart';
import 'package:rently/features/auth/presentation/auth_landing_screen.dart';
import 'package:rently/features/auth/presentation/auth_provider.dart';
import 'package:rently/features/auth/presentation/auth_ui.dart';
import 'package:rently/features/auth/presentation/sign_in_screen.dart';
import 'package:rently/features/navigation/presentation/main_navigation_shell.dart';
import 'package:rently/core/services/database_service.dart';

void main() {
  setUp(() {
    DatabaseService.instance.resetForTesting();
  });

  tearDown(() {
    DatabaseService.instance.resetForTesting();
  });

  group('Auth Flow Diagnosing Bug Feedback Loop', () {
    test('Returning student who already completed onboarding should NOT be forced to picking preferences', () async {
      final container = ProviderContainer();
      final authNotifier = container.read(authStateProvider.notifier);
      final repo = container.read(authDatabaseRepositoryProvider);

      // Pre-seed an existing student profile in database that already completed onboarding
      final existingUser = UserModel(
        uid: 'student_google_demo',
        email: 'alex.cruz@ust.edu.ph',
        displayName: 'Alex Cruz',
        role: UserRole.student,
        isVerified: true,
        school: 'University of Santo Tomas',
        photoUrl: '',
        authProvider: 'google',
        hasCompletedOnboarding: true, // ALREADY COMPLETED ONBOARDING
        lifestyleTags: ['Quiet Hours', 'Non-Smoker'],
      );
      await repo.saveUserProfile(existingUser);

      // User signs in with Google
      await authNotifier.signInWithGoogle(role: UserRole.student);

      final user = container.read(authStateProvider).value;
      expect(user, isNotNull);
      expect(user!.hasCompletedOnboarding, isTrue,
          reason: 'Returning user must keep hasCompletedOnboarding=true so they are not sent to preferences');
    });

    test('New student correctly gets hasCompletedOnboarding=false', () async {
      final container = ProviderContainer();
      final authNotifier = container.read(authStateProvider.notifier);

      // New student signs in with role
      await authNotifier.signInWithRole(
        email: 'brand_new_student@ust.edu.ph',
        displayName: 'Brand New',
        role: UserRole.student,
      );

      final user = container.read(authStateProvider).value;
      expect(user, isNotNull);
      expect(user!.hasCompletedOnboarding, isFalse,
          reason: 'New student must be routed to preferences onboarding on their first login');
    });

    test('signUpWithEmail creates a uid-scoped student profile', () async {
      final container = ProviderContainer();

      await container.read(authStateProvider.notifier).signUpWithEmail(
            email: 'new.person@ust.edu.ph',
            password: 'secret123',
            displayName: 'New Person',
            role: UserRole.student,
          );

      final user = container.read(authStateProvider).value;
      expect(user, isNotNull);
      expect(user!.uid, 'user_new_person_ust_edu_ph');
      expect(user.email, 'new.person@ust.edu.ph');
      expect(user.role, UserRole.student);
      expect(user.hasCompletedOnboarding, isFalse);
    });

    testWidgets('SignInScreen shows spinner and disables actions during auth', (tester) async {
      final container = ProviderContainer();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: SignInScreen(onBack: () {}, onCreateAccount: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);

      // Simulate loading state
      container.read(authStateProvider.notifier).state = const AsyncValue.loading();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final signInButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('sign_in_submit')),
      );
      expect(signInButton.onPressed, isNull);
    });

    testWidgets('SignInScreen displays error banner when authentication has error', (tester) async {
      final container = ProviderContainer();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: SignInScreen(onBack: () {}, onCreateAccount: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Simulate error state
      container.read(authStateProvider.notifier).state =
          AsyncValue.error(StateError('Network error'), StackTrace.current);
      await tester.pump();

      expect(find.byType(AuthErrorBanner), findsOneWidget);
      expect(find.text('Network error'), findsOneWidget);
    });

    testWidgets('Landing screen opens sign-in without asking for a role', (tester) async {
      final container = ProviderContainer();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AuthLandingScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Create an account'), findsOneWidget);
      expect(find.text('I already have an account'), findsOneWidget);

      await tester.tap(find.text('I already have an account'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome back'), findsOneWidget);
      // Role selection belongs to sign-up only; sign-in reads it from the profile.
      expect(find.text('Student'), findsNothing);
      expect(find.text('Landlord'), findsNothing);
    });

    test('Demo password mismatch explains how to reset the fixed account', () {
      const error = DemoAccountSetupRequired(email: 'host.demo@rently.ph');
      final message = authErrorMessage(error);

      expect(message, contains('host.demo@rently.ph'));
      expect(message, contains('RentlyDemo123!'));
      expect(message, contains('Firebase Console'));
    });

    testWidgets('Auth gate shows the landing screen instead of crashing on auth errors', (tester) async {
      final container = ProviderContainer();
      container.read(authStateProvider.notifier).state = AsyncValue.error(
        StateError('The supplied auth credential is incorrect'),
        StackTrace.current,
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: MainNavigationShell()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AuthLandingScreen), findsOneWidget);
      expect(find.byType(AuthErrorBanner), findsOneWidget);
      expect(
        find.text('The supplied auth credential is incorrect'),
        findsOneWidget,
      );
    });

    testWidgets('Navigating away from the landing screen clears stale auth errors', (tester) async {
      final container = ProviderContainer();
      container.read(authStateProvider.notifier).state = AsyncValue.error(
        StateError('Incorrect email or password.'),
        StackTrace.current,
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AuthLandingScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AuthErrorBanner), findsOneWidget);

      await tester.ensureVisible(find.text('I already have an account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('I already have an account'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.byType(AuthErrorBanner), findsNothing);
    });

    test('Mock identities are persisted locally without Firestore', () async {
      final container = ProviderContainer();

      await container.read(authStateProvider.notifier).signInWithRole(
            email: 'student@ust.edu.ph',
            displayName: 'Alex Cruz',
            role: UserRole.student,
          );

      final user = container.read(authStateProvider).valueOrNull;
      expect(user, isNotNull);

      final local = await container
          .read(authDatabaseRepositoryProvider)
          .fetchLocalUserProfile(user!.uid);
      expect(local, isNotNull);
      expect(local!.uid, user.uid);
    });
  });
}
