import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/user_model.dart';
import 'auth_provider.dart';
import 'auth_ui.dart';
import 'sign_in_screen.dart';
import 'sign_up_screen.dart';

enum _AuthView { landing, signIn, signUp }

/// Signed-out entry point. Signing in and creating an account are separate
/// flows: the role is only chosen when the account is created, and afterwards
/// it is always read from the user's profile.
class AuthLandingScreen extends ConsumerStatefulWidget {
  const AuthLandingScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<AuthLandingScreen> createState() => _AuthLandingScreenState();
}

class _AuthLandingScreenState extends ConsumerState<AuthLandingScreen> {
  _AuthView _view = _AuthView.landing;

  /// Clears stale sign-in errors before moving between auth screens.
  void _open(_AuthView view) {
    ref.read(authStateProvider.notifier).clearAuthError();
    setState(() => _view = view);
  }

  @override
  Widget build(BuildContext context) {
    switch (_view) {
      case _AuthView.signIn:
        return SignInScreen(
          onBack: () => _open(_AuthView.landing),
          onCreateAccount: () => _open(_AuthView.signUp),
        );
      case _AuthView.signUp:
        return SignUpScreen(
          onBack: () => _open(_AuthView.landing),
          onSignIn: () => _open(_AuthView.signIn),
        );
      case _AuthView.landing:
        return _buildLanding(context);
    }
  }

  Widget _buildLanding(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final error = authState.hasError && authState.error is! ProfileSetupRequired
        ? authState.error
        : null;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryAmber,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: const Icon(
                    Icons.home_work_rounded,
                    size: 52,
                    color: AppTheme.navyDark,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'RENTLY',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: AppTheme.navyDark,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Campus housing, matched both ways.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 36),
              const _LandingFeature(
                icon: Icons.style_rounded,
                title: 'Swipe to discover',
                subtitle: 'Find verified dorms and bedspaces near your campus.',
              ),
              const SizedBox(height: 16),
              const _LandingFeature(
                icon: Icons.handshake_rounded,
                title: 'Match both ways',
                subtitle: 'Landlords like you back before a conversation starts.',
              ),
              const SizedBox(height: 16),
              const _LandingFeature(
                icon: Icons.chat_bubble_rounded,
                title: 'Chat and book a viewing',
                subtitle: 'Agree on a schedule without leaving the app.',
              ),
              const SizedBox(height: 40),
              if (error != null) AuthErrorBanner(message: authErrorMessage(error)),
              ElevatedButton(
                onPressed: () => _open(_AuthView.signUp),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Create an account'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _open(_AuthView.signIn),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(color: Colors.grey.shade300, width: 1.5),
                  foregroundColor: AppTheme.navyDark,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('I already have an account'),
              ),
              if (kDebugMode) ...[
                const SizedBox(height: 32),
                const _DemoAccessCard(),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _LandingFeature extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _LandingFeature({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.primaryAmber.withOpacity(0.18),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: AppTheme.navyDark, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: AppTheme.navyDark,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Debug-only shortcuts so local testing never depends on OAuth app setup.
/// These map to fixed Firebase demo accounts when Auth is configured, and to
/// local demo identities otherwise.
class _DemoAccessCard extends ConsumerWidget {
  const _DemoAccessCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoading = ref.watch(authStateProvider).isLoading;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.bug_report_outlined, size: 18, color: Colors.grey.shade700),
              const SizedBox(width: 8),
              Text(
                'Demo access (debug only)',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Uses student.demo@rently.ph / host.demo@rently.ph with the shared demo password.',
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, height: 1.35),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isLoading
                      ? null
                      : () => ref
                          .read(authStateProvider.notifier)
                          .signInAsDemo(role: UserRole.student),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.navyDark,
                    side: BorderSide(color: Colors.grey.shade400),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Student demo'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: isLoading
                      ? null
                      : () => ref
                          .read(authStateProvider.notifier)
                          .signInAsDemo(role: UserRole.landlord),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.navyDark,
                    side: BorderSide(color: Colors.grey.shade400),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Host demo'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shown only while the persisted Firebase session is being restored.
class AuthSplashScreen extends StatelessWidget {
  const AuthSplashScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SplashLogo(),
            SizedBox(height: 24),
            CircularProgressIndicator(color: AppTheme.navyDark),
            SizedBox(height: 16),
            Text(
              'Restoring your session...',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _SplashLogo extends StatelessWidget {
  const _SplashLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: AppTheme.primaryAmber,
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Icon(
        Icons.home_work_rounded,
        size: 46,
        color: AppTheme.navyDark,
      ),
    );
  }
}
