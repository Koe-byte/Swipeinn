import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/user_model.dart';
import '../../auth/presentation/auth_provider.dart';
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
    final user = authState.value;
    final selectedIndex = ref.watch(navigationIndexProvider);

    if (user == null) {
      return const OnboardingScreen();
    }

    if (user.role == UserRole.student && !user.hasCompletedOnboarding) {
      return const StudentDemographicsScreen();
    }

    final isStudent = user.role == UserRole.student;

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

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  UserRole _selectedRole = UserRole.student;
  final _emailController = TextEditingController(text: 'student@ust.edu.ph');
  final _nameController = TextEditingController(text: 'Alex Cruz');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryAmber,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.home_work_rounded,
                    size: 48,
                    color: AppTheme.navyDark,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'RENTLY',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: AppTheme.navyDark,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Bilateral Campus Accommodation Matching',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Select your role to get started:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _RoleCard(
                      title: 'Student',
                      subtitle: 'Find dorms & bedspaces',
                      icon: Icons.school_rounded,
                      isSelected: _selectedRole == UserRole.student,
                      onTap: () => setState(() => _selectedRole = UserRole.student),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _RoleCard(
                      title: 'Landlord',
                      subtitle: 'List rooms & review matches',
                      icon: Icons.real_estate_agent_rounded,
                      isSelected: _selectedRole == UserRole.landlord,
                      onTap: () => setState(() => _selectedRole = UserRole.landlord),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (ref.watch(authStateProvider).hasError)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Authentication failed. Please verify provider settings and try again.',
                          style: TextStyle(color: Colors.red.shade800, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              OutlinedButton.icon(
                icon: ref.watch(authStateProvider).isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.navyDark),
                      )
                    : Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Text(
                          'G',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                label: Text(
                  ref.watch(authStateProvider).isLoading ? 'Authenticating...' : 'Continue with Google',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.navyDark,
                    fontSize: 15,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.grey.shade300, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.white,
                ),
                onPressed: ref.watch(authStateProvider).isLoading
                    ? null
                    : () {
                        ref.read(authStateProvider.notifier).signInWithGoogle(role: _selectedRole);
                      },
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.facebook, size: 24, color: Colors.white),
                label: const Text(
                  'Continue with Facebook',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    fontSize: 15,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1877F2),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                ),
                onPressed: ref.watch(authStateProvider).isLoading
                    ? null
                    : () {
                        ref.read(authStateProvider.notifier).signInWithFacebook(role: _selectedRole);
                      },
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey.shade300)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'or continue with campus email',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ),
                  Expanded(child: Divider(color: Colors.grey.shade300)),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'Campus / Contact Email',
                  hintText: 'e.g. name@campus.edu.ph',
                  helperText: _emailController.text.contains('.edu')
                      ? '✓ Institutional email detected (Instant Verified Badge)'
                      : null,
                  helperStyle: const TextStyle(color: AppTheme.verifiedBlue),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onChanged: (val) => setState(() {}),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: ref.watch(authStateProvider).isLoading
                    ? null
                    : () {
                        ref.read(authStateProvider.notifier).signInWithRole(
                              email: _emailController.text,
                              displayName: _nameController.text,
                              role: _selectedRole,
                            );
                      },
                child: const Text('Enter Rently'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryAmber.withOpacity(0.15) : Colors.white,
          border: Border.all(
            color: isSelected ? AppTheme.primaryAmber : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, size: 36, color: isSelected ? AppTheme.navyDark : AppTheme.textSecondary),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
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
    final user = ref.watch(authStateProvider).value;
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
    final user = ref.watch(authStateProvider).value;
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
