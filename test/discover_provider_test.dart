import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swipeinn/features/auth/domain/user_model.dart';
import 'package:swipeinn/features/auth/presentation/auth_provider.dart';
import 'package:swipeinn/features/listings/presentation/listings_provider.dart';

import 'support/fake_auth_repository.dart';
import 'support/fake_listings_repository.dart';

const _profile = UserModel(
  uid: 'uid-1',
  email: 'renter@example.com',
  displayName: 'Renter',
  hasCompletedOnboarding: true,
  preferences: RenterPreferences(
    propertyTypes: [PropertyType.studio],
    budgetMin: 5000,
    budgetMax: 12000,
    moveInWindow: MoveInWindow.withinMonth,
  ),
);

void main() {
  test('Discover re-subscribes after the signed-in account changes', () async {
    final auth = FakeAuthRepository(
      initialIdentity: const AuthIdentity(
        uid: 'uid-1',
        email: 'renter@example.com',
        displayName: 'Renter',
        isEmailVerified: true,
      ),
      initialProfile: _profile,
    );
    final listings = FakeListingsRepository();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        listingsRepositoryProvider.overrideWithValue(listings),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(auth.dispose);
    addTearDown(listings.dispose);

    final subscription = container.listen(
      discoverListingsProvider,
      (_, __) {},
    );
    await pumpEventQueue();

    expect(listings.watchAllSubscriptions, 1);

    auth.emit(const AuthIdentity(
      uid: 'uid-2',
      email: 'other@example.com',
      displayName: 'Other',
      isEmailVerified: true,
    ));
    await pumpEventQueue();

    expect(listings.watchAllSubscriptions, 2);

    subscription.close();
  });
}
