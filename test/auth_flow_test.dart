import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rently/features/auth/domain/user_model.dart';
import 'package:rently/features/auth/presentation/auth_provider.dart';
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

    testWidgets('OnboardingScreen displays loading indicator and disables button during auth', (tester) async {
      final container = ProviderContainer();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: OnboardingScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Continue with Google'), findsOneWidget);

      // Simulate loading state
      container.read(authStateProvider.notifier).state = const AsyncValue.loading();
      await tester.pump();

      expect(find.text('Authenticating...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('OnboardingScreen displays error container when authentication has error', (tester) async {
      final container = ProviderContainer();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: OnboardingScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Simulate error state
      container.read(authStateProvider.notifier).state = AsyncValue.error('Network error', StackTrace.current);
      await tester.pump();

      expect(find.textContaining('Authentication failed'), findsOneWidget);
    });
  });
}
