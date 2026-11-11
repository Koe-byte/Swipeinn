import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import 'auth_provider.dart';
import 'auth_ui.dart';

class SignInScreen extends ConsumerStatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onCreateAccount;

  const SignInScreen({
    Key? key,
    required this.onBack,
    required this.onCreateAccount,
  }) : super(key: key);

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email and password.')),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    await ref.read(authStateProvider.notifier).signInWithEmail(
          email: email,
          password: password,
        );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final isLoading = authState.isLoading;
    final error = authState.hasError && authState.error is! ProfileSetupRequired
        ? authState.error
        : null;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: isLoading ? null : widget.onBack,
        ),
        title: const Text('Sign In'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              const Text(
                'Welcome back',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.navyDark,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sign in to pick up where you left off. Your role and preferences are loaded from your profile.',
                style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 24),
              if (error != null) AuthErrorBanner(message: authErrorMessage(error)),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _signIn(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                key: const Key('sign_in_submit'),
                onPressed: isLoading ? null : _signIn,
                child: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.navyDark),
                      )
                    : const Text('Sign In'),
              ),
              const SizedBox(height: 20),
              const AuthOrDivider(label: 'or continue with'),
              const SizedBox(height: 16),
              _OAuthButtons(
                enabled: !isLoading,
                onGoogle: () => ref.read(authStateProvider.notifier).signInWithGoogle(),
                onFacebook: () => ref.read(authStateProvider.notifier).signInWithFacebook(),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('New to Swipeinn?', style: TextStyle(color: AppTheme.textSecondary)),
                  TextButton(
                    onPressed: isLoading ? null : widget.onCreateAccount,
                    child: const Text('Create account'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OAuthButtons extends StatelessWidget {
  final bool enabled;
  final VoidCallback onGoogle;
  final VoidCallback onFacebook;

  const _OAuthButtons({
    required this.enabled,
    required this.onGoogle,
    required this.onFacebook,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        OutlinedButton.icon(
          onPressed: enabled ? onGoogle : null,
          icon: Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: const Text('G', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w900)),
          ),
          label: const Text('Continue with Google'),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.grey.shade300, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            foregroundColor: AppTheme.navyDark,
          ),
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: enabled ? onFacebook : null,
          icon: const Icon(Icons.facebook, size: 22, color: Colors.white),
          label: const Text('Continue with Facebook'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1877F2),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }
}
