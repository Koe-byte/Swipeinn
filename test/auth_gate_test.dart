import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swipeinn/features/auth/domain/user_model.dart';
import 'package:swipeinn/features/auth/presentation/auth_provider.dart';

import 'support/fake_auth_repository.dart';

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

const _incompleteProfile = UserModel(
  uid: 'uid-1',
  email: 'renter@example.com',
  displayName: 'Renter',
);

ProviderContainer _containerFor(FakeAuthRepository fake) {
  final container = ProviderContainer(
    overrides: [authRepositoryProvider.overrideWithValue(fake)],
  );
  // Reading the provider constructs AuthNotifier, which subscribes to the
  // repository stream. Without this the notifier is created only after the
  // first pump and the suite sees the initial `restoring` status.
  container.read(authStateProvider);
  addTearDown(container.dispose);
  addTearDown(fake.dispose);
  return container;
}

void main() {
  group('AuthNotifier state machine', () {
    test('an empty session resolves to signedOut', () async {
      final container = _containerFor(FakeAuthRepository());
      await pumpEventQueue();

      expect(container.read(authStateProvider).status, AuthStatus.signedOut);
    });

    test('signing up lands on unverified with the email preserved', () async {
      final container = _containerFor(FakeAuthRepository());
      await pumpEventQueue();

      await container.read(authStateProvider.notifier).signUp(
            email: 'new@example.com',
            password: 'secret123',
            displayName: 'New Person',
          );
      await pumpEventQueue();

      final state = container.read(authStateProvider);
      expect(state.status, AuthStatus.unverified);
      expect(state.email, 'new@example.com');
      expect(state.user, isNull);
    });

    test('a verified account without preferences needs onboarding', () async {
      final fake = FakeAuthRepository(
        initialIdentity: const AuthIdentity(
          uid: 'uid-1',
          email: 'renter@example.com',
          displayName: 'Renter',
          isEmailVerified: true,
        ),
        initialProfile: _incompleteProfile,
      );
      final container = _containerFor(fake);
      await pumpEventQueue();

      expect(
          container.read(authStateProvider).status, AuthStatus.needsOnboarding);
    });

    test('a verified account with preferences is ready', () async {
      final fake = FakeAuthRepository(
        initialIdentity: const AuthIdentity(
          uid: 'uid-1',
          email: 'renter@example.com',
          displayName: 'Renter',
          isEmailVerified: true,
        ),
        initialProfile: _completeProfile,
      );
      final container = _containerFor(fake);
      await pumpEventQueue();

      expect(container.read(authStateProvider).status, AuthStatus.ready);
      expect(container.read(authStateProvider).user?.preferences?.isComplete,
          isTrue);
    });

    test('completing onboarding persists preferences and unlocks the app',
        () async {
      final fake = FakeAuthRepository(
        initialIdentity: const AuthIdentity(
          uid: 'uid-1',
          email: 'renter@example.com',
          displayName: 'Renter',
          isEmailVerified: true,
        ),
        initialProfile: _incompleteProfile,
      );
      final container = _containerFor(fake);
      await pumpEventQueue();

      final saved =
          await container.read(authStateProvider.notifier).completeOnboarding(
                const RenterPreferences(
                  propertyTypes: [PropertyType.bedspace, PropertyType.room],
                  budgetMin: 4000,
                  budgetMax: 9000,
                  areas: ['Cebu City'],
                  moveInWindow: MoveInWindow.asap,
                ),
              );
      await pumpEventQueue();

      expect(saved, isTrue);
      expect(fake.profileSaves, 1);
      final state = container.read(authStateProvider);
      expect(state.status, AuthStatus.ready);
      expect(state.user?.hasCompletedOnboarding, isTrue);
      expect(
          state.user?.preferences?.propertyTypes, contains(PropertyType.room));
      expect(fake.profile?.preferences?.budgetMax, 9000);
    });

    test('verifying the email promotes the session out of unverified',
        () async {
      final fake = FakeAuthRepository();
      final container = _containerFor(fake);
      await pumpEventQueue();

      await container.read(authStateProvider.notifier).signUp(
            email: 'new@example.com',
            password: 'secret123',
            displayName: 'New Person',
          );
      await pumpEventQueue();
      expect(container.read(authStateProvider).status, AuthStatus.unverified);

      fake.markVerifiedOnReload = true;
      await container.read(authStateProvider.notifier).refreshVerification();
      await pumpEventQueue();

      expect(
          container.read(authStateProvider).status, AuthStatus.needsOnboarding);
    });

    test('signing out clears the session', () async {
      final fake = FakeAuthRepository(
        initialIdentity: const AuthIdentity(
          uid: 'uid-1',
          email: 'renter@example.com',
          displayName: 'Renter',
          isEmailVerified: true,
        ),
        initialProfile: _completeProfile,
      );
      final container = _containerFor(fake);
      await pumpEventQueue();

      await container.read(authStateProvider.notifier).signOut();
      await pumpEventQueue();

      expect(container.read(authStateProvider).status, AuthStatus.signedOut);
      expect(container.read(authStateProvider).user, isNull);
    });

    test('password reset reaches the repository and reports success', () async {
      final fake = FakeAuthRepository();
      final container = _containerFor(fake);
      await pumpEventQueue();

      final sent = await container
          .read(authStateProvider.notifier)
          .sendPasswordReset('a@b.com');

      expect(sent, isTrue);
      expect(fake.passwordResetsSent, 1);
      expect(
          container.read(authStateProvider).infoMessage, contains('a@b.com'));
    });

    test('a profile read failure surfaces as failure and retry recovers',
        () async {
      final fake = FakeAuthRepository(
        initialIdentity: const AuthIdentity(
          uid: 'uid-1',
          email: 'renter@example.com',
          displayName: 'Renter',
          isEmailVerified: true,
        ),
        initialProfile: _completeProfile,
      )..fetchProfileError = StateError('offline');

      final container = _containerFor(fake);
      await pumpEventQueue();

      expect(container.read(authStateProvider).status, AuthStatus.failure);
      expect(container.read(authStateProvider).errorMessage, isNotNull);

      fake.fetchProfileError = null;
      await container.read(authStateProvider.notifier).retry();
      await pumpEventQueue();

      expect(container.read(authStateProvider).status, AuthStatus.ready);
    });

    test('sign-up errors are mapped to readable copy', () async {
      final fake = FakeAuthRepository()..signUpError = Exception('boom');
      final container = _containerFor(fake);
      await pumpEventQueue();

      await container.read(authStateProvider.notifier).signUp(
            email: 'new@example.com',
            password: 'secret123',
            displayName: 'New Person',
          );

      final state = container.read(authStateProvider);
      expect(state.errorMessage, isNotNull);
      expect(state.isSubmitting, isFalse);
    });

    test('a profile photo upload stores the URL and removal clears it',
        () async {
      final fake = FakeAuthRepository(
        initialIdentity: const AuthIdentity(
          uid: 'uid-1',
          email: 'renter@example.com',
          displayName: 'Renter',
          isEmailVerified: true,
        ),
        initialProfile: _completeProfile,
      );
      final container = _containerFor(fake);
      await pumpEventQueue();

      final notifier = container.read(authStateProvider.notifier);
      final uploadError = await notifier.updateProfilePhoto(
        bytes: Uint8List.fromList([1, 2, 3]),
        fileName: 'me.png',
      );
      await pumpEventQueue();

      expect(uploadError, isNull);
      expect(fake.avatarsUploaded, 1);
      expect(
        container.read(authStateProvider).user?.photoUrl,
        contains('me.png'),
      );
      expect(container.read(authStateProvider).isEmailVerified, isTrue);

      final removalError = await notifier.removeProfilePhoto();
      await pumpEventQueue();

      expect(removalError, isNull);
      expect(fake.avatarsRemoved, 1);
      expect(container.read(authStateProvider).user?.photoUrl, isEmpty);
    });

    test('resending verification targets the signed-in email', () async {
      final fake = FakeAuthRepository();
      final container = _containerFor(fake);
      await pumpEventQueue();

      await container.read(authStateProvider.notifier).signUp(
            email: 'new@example.com',
            password: 'secret123',
            displayName: 'New Person',
          );
      await pumpEventQueue();

      final sent = await container
          .read(authStateProvider.notifier)
          .resendVerificationEmail();
      await pumpEventQueue();

      expect(sent, isTrue);
      expect(fake.lastVerificationEmail, 'new@example.com');
      expect(container.read(authStateProvider).isEmailVerified, isFalse);
    });
  });
}
