import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import 'auth_provider.dart';
import 'auth_ui.dart';

/// Blocks the app until Firebase reports `emailVerified`.
class VerifyEmailScreen extends ConsumerWidget {
  const VerifyEmailScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authStateProvider);
    final notifier = ref.read(authStateProvider.notifier);
    final email = state.email ?? state.user?.email ?? 'your email';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Verify your email'),
        actions: [
          TextButton(
            onPressed: state.isSubmitting ? null : notifier.signOut,
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryAmber.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Icon(
                        Icons.mark_email_unread_outlined,
                        size: 36,
                        color: AppTheme.navyDark,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Check your inbox',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.navyDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'We sent a verification link to $email. Open it, then come back here.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (state.errorMessage != null)
                    AuthErrorBanner(message: state.errorMessage!),
                  if (state.infoMessage != null)
                    AuthInfoBanner(message: state.infoMessage!),
                  ElevatedButton(
                    key: const Key('verify_refresh'),
                    onPressed: state.isSubmitting
                        ? null
                        : notifier.refreshVerification,
                    child: state.isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.navyDark,
                            ),
                          )
                        : const Text("I've verified my email"),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: state.isSubmitting
                        ? null
                        : notifier.resendVerificationEmail,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      foregroundColor: AppTheme.navyDark,
                      side: BorderSide(color: Colors.grey.shade300, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text('Resend verification email'),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'No email after a minute? Check the spam folder before resending.',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
