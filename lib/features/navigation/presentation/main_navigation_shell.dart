import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/domain/user_model.dart';
import '../../auth/presentation/auth_landing_screen.dart';
import '../../auth/presentation/auth_provider.dart';
import '../../auth/presentation/preferences_onboarding_screen.dart';
import '../../auth/presentation/verify_email_screen.dart';
import '../../listings/presentation/landlord_studio_screen.dart';
import '../../listings/presentation/student_discovery_screen.dart';
import '../../matches/presentation/matches_screen.dart';

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
      body: pages[selectedIndex],
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

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  String _budgetLabel(RenterPreferences preferences) {
    final pesos = NumberFormat.decimalPattern();
    return '₱${pesos.format(preferences.budgetMin)} – '
        '₱${pesos.format(preferences.budgetMax)} / month';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).user;
    final preferences = user?.preferences;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: CircleAvatar(
                radius: 44,
                backgroundColor: AppTheme.primaryAmber,
                child: Text(
                  user?.displayName.isNotEmpty == true
                      ? user!.displayName[0].toUpperCase()
                      : 'S',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.navyDark,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    user?.displayName ?? 'Swipeinn user',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (user?.isOwnerVerified == true) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.verified,
                      color: AppTheme.verifiedBlue, size: 20),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              user?.email ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            if (user?.isOwnerVerified == true) ...[
              const SizedBox(height: 8),
              const Center(
                child: Chip(
                  avatar: Icon(Icons.workspace_premium, size: 16),
                  label: Text('Verified owner'),
                ),
              ),
            ],
            const SizedBox(height: 24),
            const Text(
              'Your preferences',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            if (preferences == null)
              const Text(
                'Not set yet.',
                style: TextStyle(color: AppTheme.textSecondary),
              )
            else ...[
              ListTile(
                leading: const Icon(Icons.home_work_outlined,
                    color: AppTheme.navyDark),
                title: const Text('Property types'),
                subtitle: Text(
                  preferences.propertyTypes
                      .map((type) => type.label)
                      .join(', '),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.payments_outlined,
                    color: AppTheme.navyDark),
                title: const Text('Monthly budget'),
                subtitle: Text(_budgetLabel(preferences)),
              ),
              ListTile(
                leading:
                    const Icon(Icons.place_outlined, color: AppTheme.navyDark),
                title: const Text('Preferred areas'),
                subtitle: Text(
                  preferences.areas.isEmpty
                      ? 'Anywhere'
                      : preferences.areas.join(', '),
                ),
              ),
              ListTile(
                leading:
                    const Icon(Icons.event_outlined, color: AppTheme.navyDark),
                title: const Text('Move-in window'),
                subtitle: Text(preferences.moveInWindow.label),
              ),
            ],
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => ref.read(authStateProvider.notifier).signOut(),
              child: const Text('Sign Out'),
            ),
          ],
        ),
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
