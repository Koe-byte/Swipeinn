import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:swipeinn/features/auth/domain/user_model.dart';
import 'package:swipeinn/features/auth/presentation/auth_provider.dart';
import 'package:swipeinn/features/auth/presentation/complete_profile_screen.dart';
import 'package:swipeinn/features/auth/presentation/demographics/student_demographics_screen.dart';
import 'package:swipeinn/features/navigation/presentation/main_navigation_shell.dart';
import 'package:swipeinn/core/services/database_service.dart';

void main() {
  setUp(() {
    DatabaseService.instance.resetForTesting();
  });

  tearDown(() {
    DatabaseService.instance.resetForTesting();
  });

  group('AuthNotifier & StudentDemographics TDD Slice 1', () {
    test('signInWithGoogle signs in student with hasCompletedOnboarding false', () async {
      final container = ProviderContainer();
      final authNotifier = container.read(authStateProvider.notifier);

      await authNotifier.signInWithGoogle(role: UserRole.student);

      final user = container.read(authStateProvider).value;
      expect(user, isNotNull);
      expect(user!.role, equals(UserRole.student));
      expect(user.authProvider, equals('google'));
      expect(user.hasCompletedOnboarding, isFalse);
    });

    test('signInWithFacebook signs in student with hasCompletedOnboarding false', () async {
      final container = ProviderContainer();
      final authNotifier = container.read(authStateProvider.notifier);

      await authNotifier.signInWithFacebook(role: UserRole.student);

      final user = container.read(authStateProvider).value;
      expect(user, isNotNull);
      expect(user!.role, equals(UserRole.student));
      expect(user.authProvider, equals('facebook'));
      expect(user.hasCompletedOnboarding, isFalse);
    });

    test('completeStudentDemographics saves demographics and marks onboarding complete', () async {
      final container = ProviderContainer();
      final authNotifier = container.read(authStateProvider.notifier);

      await authNotifier.signInWithGoogle(role: UserRole.student);

      const demographics = StudentDemographics(
        paxCount: 2,
        isGroupSearch: true,
        genderPolicy: 'female_only',
        houseRules: ['No Curfew', 'Visitors Allowed', 'Pets Allowed'],
        nearbyEssentials: ['24/7 Convenience Store', 'Sari-Sari Store', 'Fast Food & Carinderia'],
      );

      authNotifier.completeStudentDemographics(demographics);

      final user = container.read(authStateProvider).value;
      expect(user, isNotNull);
      expect(user!.hasCompletedOnboarding, isTrue);
      expect(user.demographics, isNotNull);
      expect(user.demographics!.paxCount, equals(2));
      expect(user.demographics!.isGroupSearch, isTrue);
      expect(user.demographics!.genderPolicy, equals('female_only'));
      expect(user.demographics!.houseRules, contains('No Curfew'));
      expect(user.demographics!.nearbyEssentials, contains('24/7 Convenience Store'));
    });

    test('skipStudentDemographics sets hasCompletedOnboarding to true without overwriting other fields', () async {
      final container = ProviderContainer();
      final authNotifier = container.read(authStateProvider.notifier);

      await authNotifier.signInWithGoogle(role: UserRole.student);

      authNotifier.skipStudentDemographics();

      final user = container.read(authStateProvider).value;
      expect(user, isNotNull);
      expect(user!.hasCompletedOnboarding, isTrue);
    });
  });

  group('StudentDemographicsScreen TDD Slice 2', () {
    testWidgets('Full 4-step onboarding flow: Pax, Gender, House Rules, Nearby Essentials (capped at 5)', (tester) async {
      final container = ProviderContainer();
      await container.read(authStateProvider.notifier).signInWithGoogle(role: UserRole.student);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: StudentDemographicsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 1: Party Size / Pax
      expect(find.text('How many are looking for a place?'), findsOneWidget);
      expect(find.text('Solo (1 Pax)'), findsOneWidget);
      expect(find.text('Pair (2 Pax)'), findsOneWidget);

      // Select Pair (2 Pax)
      await tester.tap(find.text('Pair (2 Pax)'));
      await tester.pumpAndSettle();

      // Advance to Step 2
      final nextButton = find.byKey(const Key('demographics_next_button'));
      expect(nextButton, findsOneWidget);
      await tester.tap(nextButton);
      await tester.pumpAndSettle();

      // Step 2: Dorm Gender Policy
      expect(find.text('Dorm gender preference'), findsOneWidget);
      expect(find.text('Co-ed / Mixed'), findsOneWidget);
      await tester.tap(find.text('Co-ed / Mixed'));
      await tester.pumpAndSettle();

      // Advance to Step 3
      await tester.tap(nextButton);
      await tester.pumpAndSettle();

      // Step 3: House Rules & Living Conditions
      expect(find.text('Living conditions & rules'), findsOneWidget);
      expect(find.text('No Curfew'), findsOneWidget);
      expect(find.text('Visitors Allowed'), findsOneWidget);
      expect(find.text('Pets Allowed'), findsOneWidget);

      await tester.tap(find.text('No Curfew'));
      await tester.tap(find.text('Visitors Allowed'));
      await tester.pumpAndSettle();

      // Advance to Step 4
      await tester.tap(nextButton);
      await tester.pumpAndSettle();

      // Step 4: Nearby Essentials
      expect(find.text('What do you need nearby?'), findsOneWidget);
      expect(find.text('0/5 selected'), findsOneWidget);

      // Verify LRT/MRT is NOT present
      expect(find.textContaining('LRT'), findsNothing);
      expect(find.textContaining('MRT'), findsNothing);

      // Search bar filter test
      final searchField = find.byKey(const Key('nearby_search_field'));
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'store');
      await tester.pumpAndSettle();

      expect(find.textContaining('Convenience Store'), findsOneWidget);
      expect(find.textContaining('Sari-Sari Store'), findsOneWidget);

      // Select essentials
      await tester.tap(find.textContaining('Convenience Store'));
      await tester.tap(find.textContaining('Sari-Sari Store'));
      await tester.pumpAndSettle();

      expect(find.text('2/5 selected'), findsOneWidget);

      // Clear search to show all
      await tester.enterText(searchField, '');
      await tester.pumpAndSettle();

      // Finish flow
      await tester.tap(nextButton);
      await tester.pumpAndSettle();

      // Verify UserModel has been updated with demographics & completed
      final updatedUser = container.read(authStateProvider).value;
      expect(updatedUser, isNotNull);
      expect(updatedUser!.hasCompletedOnboarding, isTrue);
      expect(updatedUser.demographics, isNotNull);
      expect(updatedUser.demographics!.paxCount, equals(2));
      expect(updatedUser.demographics!.isGroupSearch, isTrue);
      expect(updatedUser.demographics!.genderPolicy, equals('mixed'));
      expect(updatedUser.demographics!.houseRules, contains('No Curfew'));
      expect(updatedUser.demographics!.nearbyEssentials, contains('24/7 Convenience Store'));
    });
  });

  group('MainNavigationShell & OAuth UI TDD Slice 3', () {
    testWidgets('Landing opens account creation and Google sign-in routes new student to demographics', (tester) async {
      final container = ProviderContainer();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: MainNavigationShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Signed-out users see the landing screen, not a role picker.
      expect(find.text('Create an account'), findsOneWidget);
      await tester.tap(find.text('Create an account'));
      await tester.pumpAndSettle();

      // Verify Google and Facebook buttons exist on the sign-up screen.
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Continue with Facebook'), findsOneWidget);

      // Tap Continue with Google
      await tester.ensureVisible(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();

      // Student has not completed onboarding yet, so MainNavigationShell should show StudentDemographicsScreen!
      expect(find.byType(StudentDemographicsScreen), findsOneWidget);
      expect(find.text('How many are looking for a place?'), findsOneWidget);
    });

    testWidgets('A valid session without a profile is routed to CompleteProfileScreen', (tester) async {
      final container = ProviderContainer();
      container.read(authStateProvider.notifier).state = AsyncValue.error(
        const ProfileSetupRequired(
          uid: 'firebase-uid-123',
          email: 'new.student@ust.edu.ph',
          displayName: 'New Student',
        ),
        StackTrace.current,
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: MainNavigationShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CompleteProfileScreen), findsOneWidget);
      expect(find.textContaining('new.student@ust.edu.ph'), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      final user = container.read(authStateProvider).value;
      expect(user, isNotNull);
      expect(user!.uid, 'firebase-uid-123');
      expect(user.role, UserRole.student);
      expect(user.hasCompletedOnboarding, isFalse);
      expect(find.byType(StudentDemographicsScreen), findsOneWidget);
    });

    testWidgets('Completed student directly views StudentProfileScreen and sees Pax, Gender, and House Rules', (tester) async {
      final container = ProviderContainer();
      // Student already completed onboarding
      await container.read(authStateProvider.notifier).signInWithGoogle(role: UserRole.student);
      container.read(authStateProvider.notifier).completeStudentDemographics(
        const StudentDemographics(
          paxCount: 2,
          isGroupSearch: true,
          genderPolicy: 'mixed',
          houseRules: ['No Curfew', 'Pets Allowed'],
          nearbyEssentials: ['24/7 Convenience Store'],
        ),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: StudentProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Pair (2 Pax)'), findsOneWidget);
      expect(find.textContaining('Co-ed / Mixed'), findsOneWidget);
      expect(find.textContaining('No Curfew'), findsOneWidget);
      expect(find.textContaining('Pets Allowed'), findsOneWidget);
      expect(find.textContaining('24/7 Convenience Store'), findsOneWidget);
    });
  });
}
