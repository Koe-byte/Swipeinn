import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swipeinn/core/navigation/app_router.dart';
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
  int capacity = 1,
  DateTime? createdAt,
}) {
  return ListingModel(
    id: id,
    ownerUid: ownerUid,
    title: title,
    description: 'Bright studio near everything.',
    monthlyRent: rent,
    propertyType: PropertyType.studio,
    capacity: capacity,
    latitude: 14.609,
    longitude: 120.989,
    createdAt: createdAt ?? DateTime(2026, 1, 1),
  );
}

MatchModel _match({
  String ownerUid = 'uid-1',
  String requesterUid = 'uid-2',
  int messagesCount = 0,
  ViewingStatus viewingStatus = ViewingStatus.none,
  DateTime? viewingDate,
}) {
  final now = DateTime(2026, 1, 1, 12);
  return MatchModel(
    id: 'listing-1_$requesterUid',
    listingId: 'listing-1',
    listingTitle: 'Lahug Studio',
    ownerUid: ownerUid,
    requesterUid: requesterUid,
    participantUids: [ownerUid, requesterUid],
    matchedAt: now,
    expiresAt: now.add(const Duration(hours: 24)),
    messagesCount: messagesCount,
    viewingStatus: viewingStatus,
    viewingDate: viewingDate,
  );
}

Widget _appWith(
  FakeAuthRepository auth, {
  FakeListingsRepository? listings,
  FakeMatchesRepository? matches,
}) {
  final listingRepo = listings ?? FakeListingsRepository();
  final matchRepo = matches ?? FakeMatchesRepository();
  // The real approval is one database transaction. In tests the listings fake
  // asks the matches fake to create the same match.
  listingRepo.onMatchCreated = (match) async {
    await matchRepo.createMatch(match);
  };

  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      listingsRepositoryProvider.overrideWithValue(listingRepo),
      matchesRepositoryProvider.overrideWithValue(matchRepo),
    ],
    child: MaterialApp(
      onGenerateRoute: AppRouter.onGenerateRoute,
      home: const MainNavigationShell(),
    ),
  );
}

/// Advances the frame a few times without `pumpAndSettle`, because the splash
/// and submit states contain looping progress indicators.
Future<void> _advance(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
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

  testWidgets('Discover explains when the budget filter hides every listing',
      (tester) async {
    final fake = FakeAuthRepository(
      initialIdentity: _identity,
      initialProfile: _completeProfile,
    );
    final listings = FakeListingsRepository()
      ..seedListing(_listing(
        id: 'listing-2',
        ownerUid: 'uid-2',
        title: 'Lahug Loft',
        rent: 20000,
      ));

    await tester.pumpWidget(_appWith(fake, listings: listings));
    await _advance(tester);

    // The onboarding budget (₱12,000) would silently hide this listing.
    expect(find.text('Lahug Loft'), findsNothing);
    expect(find.text('No listings match your filters'), findsOneWidget);

    await tester.tap(find.byKey(const Key('discover_show_all_empty')));
    await _advance(tester);

    expect(find.byKey(const Key('discover_show_all_empty')), findsNothing);
    expect(find.text('Lahug Loft'), findsOneWidget);
  });

  testWidgets('Discover banners listings hidden by the budget filter',
      (tester) async {
    final fake = FakeAuthRepository(
      initialIdentity: _identity,
      initialProfile: _completeProfile,
    );
    final listings = FakeListingsRepository()
      ..seedListing(_listing(id: 'listing-1', rent: 6500))
      ..seedListing(_listing(
        id: 'listing-2',
        ownerUid: 'uid-2',
        title: 'Lahug Loft',
        rent: 6500,
      ))
      ..seedListing(_listing(
        id: 'listing-3',
        ownerUid: 'uid-3',
        title: 'IT Park Pad',
        rent: 20000,
      ));

    await tester.pumpWidget(_appWith(fake, listings: listings));
    await _advance(tester);

    expect(find.byKey(const Key('discover_hidden_banner')), findsOneWidget);
    expect(find.textContaining('1 listing is hidden'), findsOneWidget);

    await tester.tap(find.byKey(const Key('discover_show_all')));
    await _advance(tester);

    expect(find.byKey(const Key('discover_hidden_banner')), findsNothing);
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

  testWidgets('a published listing appears in My Listings but not in Discover',
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

    await tester.enterText(
        find.byKey(const Key('listing_title')), 'Lahug Studio');
    await tester.enterText(find.byKey(const Key('listing_rent')), '6500');
    await tester.pump();
    await tester.ensureVisible(find.text('Publish Listing Card'));
    await tester.pump();
    await tester.tap(find.text('Publish Listing Card'));
    await tester.pumpAndSettle();

    expect(find.text('Publish New Listing Card'), findsNothing);
    expect(find.text('No listings published yet.'), findsNothing);
    expect(find.text('Lahug Studio'), findsOneWidget);
    expect(find.textContaining('6500'), findsWidgets);
    expect(listings.listings.values.single.ownerUid, 'uid-1');

    await tester.tap(find.text('Discover'));
    await _advance(tester);

    // Your own place already lives in My Listings. Discover is other people's
    // deck, so it shows the dedicated "only your listings" empty state.
    expect(find.text('Discover rentals'), findsOneWidget);
    expect(find.text('Lahug Studio'), findsNothing);
    expect(find.text('No other places yet'), findsOneWidget);
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

  testWidgets('a liked card does not come back after a refresh',
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
    await tester.tap(find.byKey(const Key('discover_like')));
    await _advance(tester);

    expect(find.text('Lahug Studio'), findsNothing);

    await tester.tap(find.byKey(const Key('discover_refresh')));
    await _advance(tester);

    expect(find.text('Lahug Studio'), findsNothing);
    expect(
      find.text("You've reviewed every listing that matches your filters."),
      findsOneWidget,
    );
    await _drainSnackbars(tester);
  });

  testWidgets('passing on a card is private and survives a refresh',
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
    await tester.tap(find.byKey(const Key('discover_pass')));
    await _advance(tester);

    expect(listings.passes['uid-1'], contains('listing-2'));
    expect(find.text('Lahug Studio'), findsNothing);
    // The owner never gets a pass row in their review queue.
    expect(listings.likes['listing-2'], isNull);
    await _drainSnackbars(tester);

    // A refresh must not reset the deck; the pass is persisted.
    await tester.tap(find.byKey(const Key('discover_refresh')));
    await _advance(tester);
    expect(find.text('Lahug Studio'), findsNothing);
    expect(
      find.text("You've reviewed every listing that matches your filters."),
      findsOneWidget,
    );
  });

  testWidgets('the reviewed state can bring passed cards back',
      (tester) async {
    final fake = FakeAuthRepository(
      initialIdentity: _identity,
      initialProfile: _completeProfile,
    );
    final listings = FakeListingsRepository()
      ..seedListing(_listing(id: 'listing-2', ownerUid: 'uid-2'));

    await tester.pumpWidget(_appWith(fake, listings: listings));
    await _advance(tester);

    await tester.tap(find.byKey(const Key('discover_pass')));
    await _advance(tester);
    await _drainSnackbars(tester);

    expect(find.byKey(const Key('discover_show_passed')), findsOneWidget);
    await tester.tap(find.byKey(const Key('discover_show_passed')));
    await _advance(tester);

    expect(find.text('Lahug Studio'), findsOneWidget);
    expect(listings.passes['uid-1'], contains('listing-2'));
    await _drainSnackbars(tester);
  });

  testWidgets('the card and detail screen show how many people fit',
      (tester) async {
    final fake = FakeAuthRepository(
      initialIdentity: _identity,
      initialProfile: _completeProfile,
    );
    final listings = FakeListingsRepository()
      ..seedListing(_listing(
        id: 'listing-2',
        ownerUid: 'uid-2',
        capacity: 3,
      ));

    await tester.pumpWidget(_appWith(fake, listings: listings));
    await _advance(tester);

    expect(find.textContaining('FITS 3'), findsOneWidget);

    await tester.tap(find.text('Lahug Studio'));
    await _advance(tester);

    expect(find.text('Fits 3 people'), findsOneWidget);
    await _drainSnackbars(tester);
  });

  testWidgets('the owner can publish how many people a place fits',
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
    await tester.tap(find.byIcon(Icons.add_circle));
    await _advance(tester);

    await tester.enterText(
        find.byKey(const Key('listing_title')), 'Shared Studio');
    await tester.enterText(find.byKey(const Key('listing_rent')), '8000');

    // The form is a lazy ListView, so the stepper row does not exist until it
    // is scrolled into the built range.
    await tester.drag(find.byType(ListView), const Offset(0, -320));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('listing_capacity_plus')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('listing_capacity_plus')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('listing_capacity_plus')));
    await tester.pump();

    expect(find.text('Good for 3 people'), findsOneWidget);

    await tester.ensureVisible(find.text('Publish Listing Card'));
    await tester.pump();
    await tester.tap(find.text('Publish Listing Card'));
    await tester.pumpAndSettle();

    expect(listings.listings.values.single.capacity, 3);
    expect(find.textContaining('FITS 3'), findsOneWidget);
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

  testWidgets('rejecting a like clears the queue without opening a match',
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
    await tester.tap(find.byKey(const Key('reject_interest_uid-2')));
    await _advance(tester);

    expect(find.text('No interest yet'), findsOneWidget);
    expect(
      listings.likes['listing-1']?['uid-2']?.status,
      LikeStatus.rejected,
    );
    expect(matches.matches, isEmpty);
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

  testWidgets('the chat opens on the newest message and follows new ones',
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
        messagesCount: 30,
      ),
    );
    matches.messages['listing-1_uid-1'] = {
      for (var i = 0; i < 30; i++)
        'message-$i': MessageModel(
          id: 'message-$i',
          senderUid: 'uid-2',
          text: 'Message number $i',
          sentAt: now.add(Duration(minutes: i)),
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

    // The reversed list starts at the newest message; history is above it.
    expect(find.text('Message number 29'), findsOneWidget);
    expect(find.text('Message number 0'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Just sent this.');
    await tester.tap(find.byIcon(Icons.send));
    await _advance(tester);

    expect(find.text('Just sent this.'), findsOneWidget);
    await _drainSnackbars(tester);
  });

  testWidgets('the owner can send the first message', (tester) async {
    final fake = FakeAuthRepository(
      initialIdentity: _identity,
      initialProfile: _completeProfile,
    );
    final listings = FakeListingsRepository()..seedListing(_listing());
    final matches = FakeMatchesRepository();
    final match = _match(ownerUid: 'uid-1', requesterUid: 'uid-2');
    await matches.createMatch(match);

    await tester.pumpWidget(
      _appWith(fake, listings: listings, matches: matches),
    );
    await _advance(tester);

    await tester.tap(find.text('Matches'));
    await _advance(tester);
    await tester.tap(find.text('Lahug Studio'));
    await _advance(tester);

    final composer = tester.widget<TextField>(find.byType(TextField));
    expect(composer.enabled, isTrue);

    await tester.enterText(find.byType(TextField), 'Hello from the owner.');
    await tester.tap(find.byIcon(Icons.send));
    await _advance(tester);

    expect(
      matches.messages[match.id]?.values
          .any((message) => message.text == 'Hello from the owner.'),
      isTrue,
    );
    await _drainSnackbars(tester);
  });

  testWidgets('a renter can accept an owner-created viewing proposal',
      (tester) async {
    final fake = FakeAuthRepository(
      initialIdentity: _identity,
      initialProfile: _completeProfile,
    );
    final listings = FakeListingsRepository()
      ..seedListing(_listing(id: 'listing-1', ownerUid: 'uid-2'));
    final matches = FakeMatchesRepository();
    final viewingDate = DateTime(2026, 1, 5);
    final match = _match(
      ownerUid: 'uid-2',
      requesterUid: 'uid-1',
      messagesCount: 1,
      viewingStatus: ViewingStatus.proposed,
      viewingDate: viewingDate,
    );
    await matches.createMatch(match);
    matches.messages[match.id] = {
      'proposal-1': MessageModel(
        id: 'proposal-1',
        senderUid: 'uid-2',
        text: 'In-person inspection requested',
        type: MessageType.viewingProposal,
        viewingDate: viewingDate,
        sentAt: DateTime(2026, 1, 1, 12),
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

    expect(find.text('Viewing Proposal'), findsOneWidget);
    expect(find.byKey(const Key('accept_proposal_proposal-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('accept_proposal_proposal-1')));
    await _advance(tester);

    expect(
      matches.messages[match.id]?['proposal-1']?.proposalStatus,
      'accepted',
    );
    expect(matches.matches[match.id]?.viewingStatus, ViewingStatus.confirmed);
    expect(find.byKey(const Key('viewing_confirmed_banner')), findsOneWidget);
    await _drainSnackbars(tester);
  });

  testWidgets('an owner can accept a renter-created viewing proposal',
      (tester) async {
    final fake = FakeAuthRepository(
      initialIdentity: _identity,
      initialProfile: _completeProfile,
    );
    final listings = FakeListingsRepository()..seedListing(_listing());
    final matches = FakeMatchesRepository();
    final viewingDate = DateTime(2026, 1, 6);
    final match = _match(
      ownerUid: 'uid-1',
      requesterUid: 'uid-2',
      messagesCount: 1,
      viewingStatus: ViewingStatus.proposed,
      viewingDate: viewingDate,
    );
    await matches.createMatch(match);
    matches.messages[match.id] = {
      'proposal-2': MessageModel(
        id: 'proposal-2',
        senderUid: 'uid-2',
        text: 'In-person inspection requested',
        type: MessageType.viewingProposal,
        viewingDate: viewingDate,
        sentAt: DateTime(2026, 1, 1, 12),
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

    expect(find.byKey(const Key('accept_proposal_proposal-2')), findsOneWidget);

    await tester.tap(find.byKey(const Key('accept_proposal_proposal-2')));
    await _advance(tester);

    expect(
      matches.messages[match.id]?['proposal-2']?.proposalStatus,
      'accepted',
    );
    expect(matches.matches[match.id]?.viewingStatus, ViewingStatus.confirmed);
    await _drainSnackbars(tester);
  });

  testWidgets('the sender of a proposal cannot accept it', (tester) async {
    final fake = FakeAuthRepository(
      initialIdentity: _identity,
      initialProfile: _completeProfile,
    );
    final listings = FakeListingsRepository()
      ..seedListing(_listing(id: 'listing-1', ownerUid: 'uid-2'));
    final matches = FakeMatchesRepository();
    final viewingDate = DateTime(2026, 1, 7);
    final match = _match(
      ownerUid: 'uid-2',
      requesterUid: 'uid-1',
      messagesCount: 1,
      viewingStatus: ViewingStatus.proposed,
      viewingDate: viewingDate,
    );
    await matches.createMatch(match);
    matches.messages[match.id] = {
      'proposal-3': MessageModel(
        id: 'proposal-3',
        senderUid: 'uid-1',
        text: 'In-person inspection requested',
        type: MessageType.viewingProposal,
        viewingDate: viewingDate,
        sentAt: DateTime(2026, 1, 1, 12),
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

    expect(find.byKey(const Key('accept_proposal_proposal-3')), findsNothing);
    expect(
      find.text('Waiting for the other person to respond.'),
      findsOneWidget,
    );
    await _drainSnackbars(tester);
  });

  testWidgets('declining a proposal updates the message and the match',
      (tester) async {
    final fake = FakeAuthRepository(
      initialIdentity: _identity,
      initialProfile: _completeProfile,
    );
    final listings = FakeListingsRepository()
      ..seedListing(_listing(id: 'listing-1', ownerUid: 'uid-2'));
    final matches = FakeMatchesRepository();
    final viewingDate = DateTime(2026, 1, 8);
    final match = _match(
      ownerUid: 'uid-2',
      requesterUid: 'uid-1',
      messagesCount: 1,
      viewingStatus: ViewingStatus.proposed,
      viewingDate: viewingDate,
    );
    await matches.createMatch(match);
    matches.messages[match.id] = {
      'proposal-4': MessageModel(
        id: 'proposal-4',
        senderUid: 'uid-2',
        text: 'In-person inspection requested',
        type: MessageType.viewingProposal,
        viewingDate: viewingDate,
        sentAt: DateTime(2026, 1, 1, 12),
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

    await tester.tap(find.byKey(const Key('decline_proposal_proposal-4')));
    await _advance(tester);

    expect(
      matches.messages[match.id]?['proposal-4']?.proposalStatus,
      'declined',
    );
    expect(matches.matches[match.id]?.viewingStatus, ViewingStatus.declined);
    expect(find.text('Viewing declined'), findsOneWidget);
    await _drainSnackbars(tester);
  });

  testWidgets('deleting a listing keeps its existing conversation',
      (tester) async {
    final fake = FakeAuthRepository(
      initialIdentity: _identity,
      initialProfile: _completeProfile,
    );
    final listings = FakeListingsRepository()..seedListing(_listing());
    final matches = FakeMatchesRepository();
    final match = _match(
      ownerUid: 'uid-1',
      requesterUid: 'uid-2',
      messagesCount: 1,
    );
    await matches.createMatch(match);
    matches.messages[match.id] = {
      'message-1': MessageModel(
        id: 'message-1',
        senderUid: 'uid-2',
        text: 'See you Saturday.',
        sentAt: DateTime(2026, 1, 1, 12),
      ),
    };

    await tester.pumpWidget(
      _appWith(fake, listings: listings, matches: matches),
    );
    await _advance(tester);

    await tester.tap(find.text('My Listings'));
    await _advance(tester);
    await tester.tap(find.text('Lahug Studio'));
    await _advance(tester);
    await tester.tap(find.byKey(const Key('listing_delete')));
    await _advance(tester);
    await tester.tap(find.byKey(const Key('listing_delete_confirm')));
    await tester.pumpAndSettle();

    expect(listings.listings['listing-1']?.isDeleted, isTrue);
    expect(find.text('No listings published yet.'), findsOneWidget);

    await tester.tap(find.text('Matches'));
    await _advance(tester);
    expect(find.text('Lahug Studio'), findsOneWidget);

    await tester.tap(find.text('Lahug Studio'));
    await _advance(tester);
    expect(find.text('See you Saturday.'), findsOneWidget);
    await _drainSnackbars(tester);
  });

  testWidgets('tapping a listing card opens the full detail screen',
      (tester) async {
    final fake = FakeAuthRepository(
      initialIdentity: _identity,
      initialProfile: _completeProfile,
    );
    final listings = FakeListingsRepository()
      ..seedListing(_listing(id: 'listing-2', ownerUid: 'uid-2'));

    await tester.pumpWidget(_appWith(fake, listings: listings));
    await _advance(tester);

    await tester.tap(find.text('Lahug Studio'));
    await _advance(tester);

    expect(find.text('Listing details'), findsOneWidget);
    expect(find.text('About this place'), findsOneWidget);
    expect(find.textContaining('₱6500 / month'), findsOneWidget);
    expect(find.byKey(const Key('listing_interest')), findsOneWidget);
    expect(find.byKey(const Key('listing_edit')), findsNothing);

    await tester.pageBack();
    await _advance(tester);
    await _drainSnackbars(tester);
  });

  testWidgets('interest sent from the detail screen reaches the owner queue',
      (tester) async {
    final fake = FakeAuthRepository(
      initialIdentity: _identity,
      initialProfile: _completeProfile,
    );
    final listings = FakeListingsRepository()
      ..seedListing(_listing(id: 'listing-2', ownerUid: 'uid-2'));

    await tester.pumpWidget(_appWith(fake, listings: listings));
    await _advance(tester);

    await tester.tap(find.text('Lahug Studio'));
    await _advance(tester);
    await tester.tap(find.byKey(const Key('listing_interest')));
    await tester.pumpAndSettle();

    final like = listings.likes['listing-2']?['uid-1'];
    expect(like, isNotNull);
    expect(like?.status, LikeStatus.pending);

    // The detail screen closes and the deck advances, matching a right swipe.
    expect(find.text('Listing details'), findsNothing);
    expect(
      find.text("You've reviewed every listing that matches your filters."),
      findsOneWidget,
    );
    await _drainSnackbars(tester);
  });

  testWidgets('the owner can edit a listing from its detail screen',
      (tester) async {
    final fake = FakeAuthRepository(
      initialIdentity: _identity,
      initialProfile: _completeProfile,
    );
    final listings = FakeListingsRepository()..seedListing(_listing());

    await tester.pumpWidget(_appWith(fake, listings: listings));
    await _advance(tester);

    await tester.tap(find.text('My Listings'));
    await _advance(tester);
    await tester.tap(find.text('Lahug Studio'));
    await _advance(tester);

    expect(
        find.text('This is your listing. Interest from other accounts shows '
            'up in the Review Queue.'),
        findsOneWidget);

    await tester.tap(find.byKey(const Key('listing_edit')));
    await _advance(tester);

    expect(find.text('Edit listing'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('listing_title')),
      'Lahug Studio Deluxe',
    );
    await tester.enterText(find.byKey(const Key('listing_rent')), '7200');
    await tester.pump();
    await tester.tap(find.byKey(const Key('listing_save')));
    await tester.pumpAndSettle();

    final saved = listings.listings['listing-1'];
    expect(saved?.title, 'Lahug Studio Deluxe');
    expect(saved?.monthlyRent, 7200);
    expect(find.text('Lahug Studio Deluxe'), findsOneWidget);
    expect(find.textContaining('₱7200 / month'), findsOneWidget);

    await _drainSnackbars(tester);
  });

  testWidgets('the owner can delete a listing after confirming',
      (tester) async {
    final fake = FakeAuthRepository(
      initialIdentity: _identity,
      initialProfile: _completeProfile,
    );
    final listings = FakeListingsRepository()..seedListing(_listing());

    await tester.pumpWidget(_appWith(fake, listings: listings));
    await _advance(tester);

    await tester.tap(find.text('My Listings'));
    await _advance(tester);
    await tester.tap(find.text('Lahug Studio'));
    await _advance(tester);

    await tester.tap(find.byKey(const Key('listing_delete')));
    await _advance(tester);
    expect(find.text('Delete listing?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('listing_delete_confirm')));
    await tester.pumpAndSettle();

    // Soft delete keeps the row (and therefore its chats) but hides it.
    expect(listings.listings['listing-1'], isNotNull);
    expect(listings.listings['listing-1']?.isDeleted, isTrue);
    expect(find.text('Listing details'), findsNothing);
    expect(find.text('No listings published yet.'), findsOneWidget);
    await _drainSnackbars(tester);
  });

  testWidgets('the profile screen renames the account', (tester) async {
    final fake = FakeAuthRepository(
      initialIdentity: _identity,
      initialProfile: _completeProfile,
    );

    await tester.pumpWidget(_appWith(fake));
    await _advance(tester);

    await tester.tap(find.text('Profile'));
    await _advance(tester);

    await tester.tap(find.byKey(const Key('profile_edit_name')));
    await _advance(tester);
    await tester.enterText(
      find.byKey(const Key('profile_name_field')),
      'Maria Santos',
    );
    await tester.tap(find.byKey(const Key('profile_name_save')));
    await _advance(tester);

    expect(fake.profile?.displayName, 'Maria Santos');
    expect(find.text('Maria Santos'), findsOneWidget);
    await _drainSnackbars(tester);
  });

  testWidgets('preferences can be edited from the profile', (tester) async {
    final fake = FakeAuthRepository(
      initialIdentity: _identity,
      initialProfile: _completeProfile,
    );

    await tester.pumpWidget(_appWith(fake));
    await _advance(tester);

    await tester.tap(find.text('Profile'));
    await _advance(tester);
    await tester.tap(find.byKey(const Key('profile_edit_prefs')));
    await _advance(tester);

    expect(find.text('Edit preferences'), findsOneWidget);
    expect(find.text('Step 1 of 2'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Apartment'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('prefs_next')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('prefs_finish')));
    await _advance(tester);

    final saved = fake.profile?.preferences;
    expect(saved?.propertyTypes, contains(PropertyType.studio));
    expect(saved?.propertyTypes, contains(PropertyType.apartment));
    expect(find.text('Preferences updated.'), findsOneWidget);
    await _drainSnackbars(tester);
  });
}
