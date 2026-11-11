import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/user_model.dart';
import '../../auth/presentation/auth_landing_screen.dart';
import '../../auth/presentation/auth_provider.dart';
import '../../auth/presentation/complete_profile_screen.dart';
import '../../listings/presentation/student_discovery_screen.dart';
import '../../listings/presentation/landlord_studio_screen.dart';
import '../../matches/presentation/matches_screen.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/demographics/student_demographics_screen.dart';

final navigationIndexProvider = StateProvider<int>((ref) => 0);

class MainNavigationShell extends ConsumerWidget {
  const MainNavigationShell({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final authNotifier = ref.read(authStateProvider.notifier);

    // Splash only while the persisted session is being restored. Manual
    // sign-in/sign-up loading keeps the current screen (with its own spinner).
    if (!authNotifier.isInitialRestoreComplete) {
      return const AuthSplashScreen();
    }

    if (authState.hasError && authState.error is ProfileSetupRequired) {
      return const CompleteProfileScreen();
    }

    final user = authState.valueOrNull;
    if (user == null) {
      return const AuthLandingScreen();
    }

    if (user.role == UserRole.student && !user.hasCompletedOnboarding) {
      return const StudentDemographicsScreen();
    }

    final isStudent = user.role == UserRole.student;
    final selectedIndex = ref.watch(navigationIndexProvider);

    final pages = isStudent
        ? [
            const StudentDiscoveryScreen(),
            const MatchesScreen(),
            const StudentProfileScreen(),
          ]
        : [
            const LandlordStudioScreen(),
            const MatchesScreen(),
            const LandlordProfileScreen(),
          ];

    return Scaffold(
      body: pages[selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) =>
            ref.read(navigationIndexProvider.notifier).state = index,
        destinations: isStudent
            ? const [
                NavigationDestination(
                  icon: Icon(Icons.style_outlined),
                  selectedIcon: Icon(Icons.style, color: AppTheme.navyDark),
                  label: 'Discover',
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
              ]
            : const [
                NavigationDestination(
                  icon: Icon(Icons.apartment_outlined),
                  selectedIcon: Icon(Icons.apartment, color: AppTheme.navyDark),
                  label: 'My Listings',
                ),
                NavigationDestination(
                  icon: Icon(Icons.mark_chat_unread_outlined),
                  selectedIcon: Icon(Icons.mark_chat_unread, color: AppTheme.navyDark),
                  label: 'Chats',
                ),
                NavigationDestination(
                  icon: Icon(Icons.storefront_outlined),
                  selectedIcon: Icon(Icons.storefront, color: AppTheme.navyDark),
                  label: 'Host Profile',
                ),
              ],
      ),
    );
  }
}

class StudentProfileScreen extends ConsumerWidget {
  const StudentProfileScreen({Key? key}) : super(key: key);

  String _formatPax(int pax, bool isGroup) {
    if (pax == 1) return 'Solo (1 Pax)';
    if (pax == 2) return 'Pair (2 Pax)';
    if (pax == 3) return 'Trio (3 Pax)';
    return 'Squad ($pax+ Pax)';
  }

  String _formatGender(String policy) {
    switch (policy) {
      case 'female_only':
        return 'All-Female';
      case 'male_only':
        return 'All-Male';
      case 'mixed':
        return 'Co-ed / Mixed';
      default:
        return 'Any / Flexible';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final demographics = user?.demographics;

    return Scaffold(
      appBar: AppBar(title: const Text('Student Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            CircleAvatar(
              radius: 44,
              backgroundColor: AppTheme.primaryAmber,
              child: Text(
                user?.displayName.isNotEmpty == true ? user!.displayName[0] : 'S',
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppTheme.navyDark),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  user?.displayName ?? 'Student',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                if (user?.isVerified == true) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.verified, color: AppTheme.verifiedBlue, size: 20),
                ]
              ],
            ),
            const SizedBox(height: 4),
            Text(user?.school ?? 'University', style: const TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.groups_outlined, color: AppTheme.navyDark),
              title: const Text('Party Size (Pax)'),
              subtitle: Text(
                demographics != null
                    ? _formatPax(demographics.paxCount, demographics.isGroupSearch)
                    : 'Solo (1 Pax)',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.wc_outlined, color: AppTheme.navyDark),
              title: const Text('Dorm Gender Preference'),
              subtitle: Text(
                demographics != null
                    ? _formatGender(demographics.genderPolicy)
                    : 'Flexible',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.attach_money, color: AppTheme.navyDark),
              title: const Text('Monthly Budget Ceiling'),
              subtitle: Text('₱${user?.budgetMax.toStringAsFixed(0)}'),
            ),
            const SizedBox(height: 12),
            if (demographics != null && demographics.houseRules.isNotEmpty) ...[
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'House Rules & Living Habits',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: demographics.houseRules
                      .map((rule) => Chip(
                            label: Text(rule),
                            backgroundColor: Colors.amber.shade50,
                            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.navyDark),
                          ))
                      .toList(),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (demographics != null && demographics.nearbyEssentials.isNotEmpty) ...[
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Nearby Essentials',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: demographics.nearbyEssentials
                      .map((essential) => Chip(
                            label: Text(essential),
                            backgroundColor: Colors.blue.shade50,
                            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.navyDark),
                          ))
                      .toList(),
                ),
              ),
              const SizedBox(height: 16),
            ],
            const SizedBox(height: 20),
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

class LandlordProfileScreen extends ConsumerWidget {
  const LandlordProfileScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Landlord Profile')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            CircleAvatar(
              radius: 44,
              backgroundColor: AppTheme.navyDark,
              child: const Icon(Icons.storefront, size: 40, color: AppTheme.primaryAmber),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  user?.displayName ?? 'Host',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.verified, color: AppTheme.verifiedBlue, size: 20),
              ],
            ),
            const SizedBox(height: 4),
            const Text('Verified Host / Property Owner', style: TextStyle(color: AppTheme.textSecondary)),
            const Spacer(),
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
