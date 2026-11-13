import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swipeinn/core/services/database_service.dart';
import 'package:swipeinn/features/auth/domain/user_model.dart';
import 'package:swipeinn/features/auth/presentation/auth_provider.dart';
import 'package:swipeinn/features/navigation/presentation/main_navigation_shell.dart';

import 'support/fake_auth_repository.dart';

const _identity = AuthIdentity(
  uid: 'uid-1',
  email: 'renter@example.com',
  displayName: 'Renter',
  isEmailVerified: true,
);

const _profileWithoutPreferences = UserModel(
  uid: 'uid-1',
  email: 'renter@example.com',
  displayName: 'Renter',
);

const _completeProfile = UserModel(
  uid: 'uid-1',
  email: 'renter@example.com',
  displayName: 'Renter',
  hasCompletedOnboarding: true,
  preferences: RenterPreferences(
    propertyTypes: [PropertyType.studio],
    budgetMin: 5000,
    budgetMax: 12000,
    areas: ['Lahug'],
    moveInWindow: MoveInWindow.withinMonth,
  ),
);

Widget _appWith(FakeAuthRepository fake) {
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(fake)],
    child: const MaterialApp(home: MainNavigationShell()),
  );
}

/// Advances the frame a few times without `pumpAndSettle`, because the splash
/// and submit states contain looping progress indicators.
Future<void> _advance(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    DatabaseService.instance.resetForTesting();
  });

  testWidgets('signed-out visitors land on the public entry screen',
      (tester) async {
    final fake = FakeAuthRepository();

    await tester.pumpWidget(_appWith(fake));
    await _advance(tester);

    expect(find.text('SWIPEINN'), findsOneWidget);
    expect(find.text('Create an account'), findsOneWidget);
    expect(find.text('I already have an account'), findsOneWidget);
  });

  testWidgets('an unverified account is stopped at the verification gate',
      (tester) async {
    final fake = FakeAuthRepository(
      initialIdentity: const AuthIdentity(
        uid: 'uid-1',
        email: 'renter@example.com',
        displayName: 'Renter',
        isEmailVerified: false,
      ),
    );

    await tester.pumpWidget(_appWith(fake));
    await _advance(tester);

    expect(find.text('Check your inbox'), findsOneWidget);
    expect(find.byKey(const Key('verify_refresh')), findsOneWidget);
    expect(find.text('Resend verification email'), findsOneWidget);
  });

  testWidgets('a verified account without preferences must onboard first',
      (tester) async {
    final fake = FakeAuthRepository(
      initialIdentity: _identity,
      initialProfile: _profileWithoutPreferences,
    );

    await tester.pumpWidget(_appWith(fake));
    await _advance(tester);

    expect(find.text('Step 1 of 2'), findsOneWidget);
    expect(find.byKey(const Key('prefs_next')), findsOneWidget);
    expect(find.text('Discover'), findsNothing);
  });

  testWidgets('the two-step onboarding persists answers and opens the app',
      (tester) async {
    final fake = FakeAuthRepository(
      initialIdentity: _identity,
      initialProfile: _profileWithoutPreferences,
    );

    await tester.pumpWidget(_appWith(fake));
    await _advance(tester);

    await tester.tap(find.widgetWithText(FilterChip, 'Studio'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('prefs_next')));
    await tester.pump();

    expect(find.text('Step 2 of 2'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Lahug, Cebu City');
    await tester.pump();
    await tester.tap(find.byKey(const Key('prefs_finish')));
    await _advance(tester);

    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);

    final saved = fake.profile;
    expect(saved?.hasCompletedOnboarding, isTrue);
    expect(saved?.preferences?.propertyTypes, contains(PropertyType.studio));
    expect(saved?.preferences?.areas, contains('Lahug'));
  });

  testWidgets('a fully onboarded account gets the four-tab shell',
      (tester) async {
    final fake = FakeAuthRepository(
      initialIdentity: _identity,
      initialProfile: _completeProfile,
    );

    await tester.pumpWidget(_appWith(fake));
    await _advance(tester);

    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('My Listings'), findsOneWidget);
    expect(find.text('Matches'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('No listings yet'), findsOneWidget);
  });

  testWidgets('the profile tab shows the saved preferences and owner badge',
      (tester) async {
    final fake = FakeAuthRepository(
      initialIdentity: _identity,
      initialProfile: _completeProfile.copyWith(isOwnerVerified: true),
    );

    await tester.pumpWidget(_appWith(fake));
    await _advance(tester);

    await tester.tap(find.text('Profile'));
    await tester.pump();

    expect(find.text('Verified owner'), findsOneWidget);
    expect(find.text('Studio'), findsOneWidget);
    expect(find.text('₱5,000 – ₱12,000 / month'), findsOneWidget);
    expect(find.text('Lahug'), findsOneWidget);
  });

  testWidgets('a published listing appears in My Listings and in Discover',
      (tester) async {
    final fake = FakeAuthRepository(
      initialIdentity: _identity,
      initialProfile: _completeProfile,
    );

    await tester.pumpWidget(_appWith(fake));
    await _advance(tester);

    await tester.tap(find.text('My Listings'));
    await tester.pump();
    expect(find.text('No listings published yet.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add_circle));
    await _advance(tester);
    expect(find.text('Publish New Listing Card'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'Lahug Studio');
    await tester.enterText(find.byType(TextField).at(2), '6500');
    await tester.pump();
    await tester.ensureVisible(find.text('Publish Listing Card'));
    await tester.pump();
    await tester.tap(find.text('Publish Listing Card'));
    await _advance(tester);

    expect(find.text('Publish New Listing Card'), findsNothing);
    expect(find.text('No listings published yet.'), findsNothing);
    expect(find.text('Lahug Studio'), findsOneWidget);
    expect(find.textContaining('6500'), findsWidgets);

    await tester.tap(find.text('Discover'));
    await _advance(tester);

    expect(find.text('Discover rentals'), findsOneWidget);
    expect(find.text('Lahug Studio'), findsOneWidget);
  });

  testWidgets('liking a place and approving it opens a chat match',
      (tester) async {
    final fake = FakeAuthRepository(
      initialIdentity: _identity,
      initialProfile: _completeProfile,
    );

    await tester.pumpWidget(_appWith(fake));
    await _advance(tester);

    // Publish a place.
    await tester.tap(find.text('My Listings'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add_circle));
    await _advance(tester);
    await tester.enterText(find.byType(TextField).at(0), 'Lahug Studio');
    await tester.enterText(find.byType(TextField).at(2), '6500');
    await tester.pump();
    await tester.ensureVisible(find.text('Publish Listing Card'));
    await tester.pump();
    await tester.tap(find.text('Publish Listing Card'));
    await _advance(tester);
    expect(find.text('Publish New Listing Card'), findsNothing);
    expect(find.text('Lahug Studio'), findsOneWidget);
    // Let the confirmation snackbar clear the navigation bar.
    await tester.pump(const Duration(seconds: 5));

    // Like it from Discover.
    await tester.tap(find.text('Discover'));
    await _advance(tester);
    expect(find.text('Discover rentals'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.favorite));
    await _advance(tester);

    // Approve the interest from My Listings.
    await tester.tap(find.text('My Listings'));
    await _advance(tester);
    await tester.tap(find.text('Review Queue'));
    await _advance(tester);
    expect(find.text('Approve'), findsOneWidget);
    await tester.tap(find.text('Approve'));
    await _advance(tester);
    expect(find.text('No interest yet'), findsOneWidget);

    // Back to the tab shell, then open Matches.
    await tester.pageBack();
    await _advance(tester);
    await tester.tap(find.text('Matches'));
    await _advance(tester);
    expect(find.text('Lahug Studio'), findsOneWidget);
    expect(find.text('Waiting for the first message'), findsOneWidget);

    // Drain the snackbar timers and their exit animations before teardown.
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
  });
}
