import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/auth_landing_screen.dart';
import '../../auth/presentation/auth_provider.dart';
import '../../auth/presentation/preferences_onboarding_screen.dart';
import '../../auth/presentation/verify_email_screen.dart';
import '../../listings/presentation/landlord_studio_screen.dart';
import '../../listings/presentation/student_discovery_screen.dart';
import '../../matches/presentation/matches_screen.dart';
import '../../profile/presentation/profile_screen.dart';

final navigationIndexProvider = StateProvider<int>((ref) => 0);

/// The auth gate. Every account gets the same four tabs: browsing, listing,
/// matches, and profile. There is no renter/owner mode to choose.
class MainNavigationShell extends ConsumerWidget {
  const MainNavigationShell({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authStateProvider);
    final notifier = ref.read(authStateProvider.notifier);

    switch (state.status) {
      case AuthStatus.restoring:
        return const AuthSplashScreen();
      case AuthStatus.failure:
        return _ConnectionErrorScreen(
          message: state.errorMessage ??
              'Could not reach Swipeinn. Check your connection.',
          onRetry: notifier.retry,
        );
      case AuthStatus.signedOut:
        return const AuthLandingScreen();
      case AuthStatus.unverified:
        return const VerifyEmailScreen();
      case AuthStatus.needsOnboarding:
        return const PreferencesOnboardingScreen();
      case AuthStatus.ready:
        return const _AccountShell();
    }
  }
}

class _AccountShell extends ConsumerWidget {
  const _AccountShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(navigationIndexProvider);

    const pages = [
      StudentDiscoveryScreen(),
      LandlordStudioScreen(),
      MatchesScreen(),
      ProfileScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) =>
            ref.read(navigationIndexProvider.notifier).state = index,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.style_outlined),
            selectedIcon: Icon(Icons.style, color: AppTheme.navyDark),
            label: 'Discover',
          ),
          NavigationDestination(
            icon: Icon(Icons.apartment_outlined),
            selectedIcon: Icon(Icons.apartment, color: AppTheme.navyDark),
            label: 'My Listings',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble, color: AppTheme.navyDark),
            label: 'Matches',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: AppTheme.navyDark),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _ConnectionErrorScreen extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ConnectionErrorScreen({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off,
                  size: 48, color: AppTheme.textSecondary),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                  onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      ),
    );
  }
}
