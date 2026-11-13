import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swipeinn/core/services/database_service.dart';
import 'package:swipeinn/features/auth/domain/user_model.dart';
import 'package:swipeinn/features/auth/presentation/auth_provider.dart';
import 'package:swipeinn/features/listings/domain/listing_model.dart';
import 'package:swipeinn/features/listings/presentation/listings_provider.dart';
import 'package:swipeinn/features/matches/domain/match_model.dart';
import 'package:swipeinn/features/matches/presentation/matches_provider.dart';
import 'package:swipeinn/features/navigation/presentation/main_navigation_shell.dart';

import 'support/fake_auth_repository.dart';
import 'support/fake_listings_repository.dart';
import 'support/fake_matches_repository.dart';

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

ListingModel _listing({
  String id = 'listing-1',
  String ownerUid = 'uid-1',
  String title = 'Lahug Studio',
  double rent = 6500,
}) {
  return ListingModel(
    id: id,
    ownerUid: ownerUid,
    title: title,
    description: 'Bright studio near everything.',
    monthlyRent: rent,
    propertyType: PropertyType.studio,
    latitude: 14.609,
    longitude: 120.989,
    createdAt: DateTime(2026, 1, 1),
  );
}

Widget _appWith(
  FakeAuthRepository auth, {
  FakeListingsRepository? listings,
  FakeMatchesRepository? matches,
}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      listingsRepositoryProvider
          .overrideWithValue(listings ?? FakeListingsRepository()),
      matchesRepositoryProvider
          .overrideWithValue(matches ?? FakeMatchesRepository()),
    ],
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

/// Drains snackbar timers and exit animations before the test binding tears
/// down.
Future<void> _drainSnackbars(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 500));
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
    expect(find.text('No places to discover yet'), findsOneWidget);
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
    final listings = FakeListingsRepository();

    await tester.pumpWidget(_appWith(fake, listings: listings));
    await _advance(tester);

    await tester.tap(find.text('My Listings'));
    await _advance(tester);
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
    expect(listings.listings.values.single.ownerUid, 'uid-1');

    await tester.tap(find.text('Discover'));
    await _advance(tester);

    expect(find.text('Discover rentals'), findsOneWidget);
    expect(find.text('Lahug Studio'), findsOneWidget);
    expect(find.text('YOUR LISTING'), findsOneWidget);

    // Liking your own place must not create a self-match.
    await tester.tap(find.byIcon(Icons.favorite));
    await _advance(tester);
    expect(listings.likes, isEmpty);
    await _drainSnackbars(tester);
  });

  testWidgets('liking someone else\'s place sends it to their review queue',
      (tester) async {
    final fake = FakeAuthRepository(
      initialIdentity: _identity,
      initialProfile: _completeProfile,
    );
    final listings = FakeListingsRepository()
      ..seedListing(_listing(id: 'listing-2', ownerUid: 'uid-2'));

    await tester.pumpWidget(_appWith(fake, listings: listings));
    await _advance(tester);

    expect(find.text('Lahug Studio'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.favorite));
    await _advance(tester);

    final like = listings.likes['listing-2']?['uid-1'];
    expect(like, isNotNull);
    expect(like?.requesterName, 'Renter');
    expect(like?.status, LikeStatus.pending);
    await _drainSnackbars(tester);
  });

  testWidgets('approving a like opens a match both sides can see',
      (tester) async {
    final fake = FakeAuthRepository(
      initialIdentity: _identity,
      initialProfile: _completeProfile,
    );
    final listings = FakeListingsRepository()
      ..seedListing(_listing())
      ..seedLike(
        ListingLike(
          listingId: 'listing-1',
          requesterUid: 'uid-2',
          requesterName: 'Maria Santos',
          likedAt: DateTime(2026, 1, 1),
        ),
      );
    final matches = FakeMatchesRepository();

    await tester.pumpWidget(
      _appWith(fake, listings: listings, matches: matches),
    );
    await _advance(tester);

    await tester.tap(find.text('My Listings'));
    await _advance(tester);
    await tester.tap(find.text('Review Queue'));
    await _advance(tester);

    expect(find.text('Maria Santos'), findsOneWidget);
    await tester.tap(find.text('Approve'));
    await _advance(tester);
    expect(find.text('No interest yet'), findsOneWidget);

    final match = matches.matches['listing-1_uid-2'];
    expect(match, isNotNull);
    expect(match?.ownerUid, 'uid-1');
    expect(match?.requesterUid, 'uid-2');
    expect(match?.participantUids, containsAll(['uid-1', 'uid-2']));
    expect(match?.listingTitle, 'Lahug Studio');
    expect(listings.likes['listing-1']?['uid-2']?.status, LikeStatus.approved);

    // Back to the tab shell, then open Matches.
    await tester.pageBack();
    await _advance(tester);
    await tester.tap(find.text('Matches'));
    await _advance(tester);
    expect(find.text('Lahug Studio'), findsOneWidget);
    expect(find.text('Waiting for the first message'), findsOneWidget);

    await _drainSnackbars(tester);
  });

  testWidgets('a match message is written and shown in the chat',
      (tester) async {
    final fake = FakeAuthRepository(
      initialIdentity: _identity,
      initialProfile: _completeProfile,
    );
    final listings = FakeListingsRepository()..seedListing(_listing());
    final matches = FakeMatchesRepository();
    final now = DateTime(2026, 1, 1, 12);
    await matches.createMatch(
      MatchModel(
        id: 'listing-1_uid-1',
        listingId: 'listing-1',
        listingTitle: 'Lahug Studio',
        ownerUid: 'uid-2',
        requesterUid: 'uid-1',
        participantUids: const ['uid-2', 'uid-1'],
        matchedAt: now,
        expiresAt: now.add(const Duration(hours: 24)),
        messagesCount: 1,
      ),
    );
    matches.messages['listing-1_uid-1'] = {
      'seed': MessageModel(
        id: 'seed',
        senderUid: 'uid-2',
        text: 'Hello! When would you like to view?',
        sentAt: now,
      ),
    };

    await tester.pumpWidget(
      _appWith(fake, listings: listings, matches: matches),
    );
    await _advance(tester);

    await tester.tap(find.text('Matches'));
    await _advance(tester);
    await tester.tap(find.text('Lahug Studio'));
    await _advance(tester);

    expect(find.text('Hello! When would you like to view?'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Saturday morning works.');
    await tester.tap(find.byIcon(Icons.send));
    await _advance(tester);

    expect(find.text('Saturday morning works.'), findsOneWidget);
    expect(
      matches.messages['listing-1_uid-1']?.values
          .any((message) => message.text == 'Saturday morning works.'),
      isTrue,
    );
    await _drainSnackbars(tester);
  });
}
