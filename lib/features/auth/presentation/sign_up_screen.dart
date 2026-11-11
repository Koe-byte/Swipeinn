import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/user_model.dart';
import 'auth_provider.dart';
import 'auth_ui.dart';
import 'role_selector.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onSignIn;

  const SignUpScreen({
    Key? key,
    required this.onBack,
    required this.onSignIn,
  }) : super(key: key);

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  UserRole _role = UserRole.student;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      _showMessage('Fill in your name, email, and password.');
      return;
    }
    if (password.length < 6) {
      _showMessage('Use a password with at least 6 characters.');
      return;
    }
    if (password != confirm) {
      _showMessage('Passwords do not match.');
      return;
    }

    FocusScope.of(context).unfocus();
    await ref.read(authStateProvider.notifier).signUpWithEmail(
          email: email,
          password: password,
          displayName: name,
          role: _role,
        );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
        title: const Text('Create Account'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Join Swipeinn',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.navyDark,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Pick your role once. We will remember it, so you never have to choose it again when signing in.',
                style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 20),
              RoleSelector(
                selected: _role,
                onChanged: isLoading ? (_) {} : (role) => setState(() => _role = role),
              ),
              const SizedBox(height: 20),
              if (error != null) AuthErrorBanner(message: authErrorMessage(error)),
              TextField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Full name',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: _role == UserRole.student ? 'Campus / contact email' : 'Contact email',
                  hintText: 'e.g. name@campus.edu.ph',
                  helperText: _emailController.text.toLowerCase().contains('.edu')
                      ? 'Institutional email detected: instant verified badge'
                      : null,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: 'At least 6 characters',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmController,
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _signUp(),
                decoration: InputDecoration(
                  labelText: 'Confirm password',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: isLoading ? null : _signUp,
                child: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.navyDark),
                      )
                    : const Text('Create Account'),
              ),
              const SizedBox(height: 20),
              const AuthOrDivider(label: 'or sign up with'),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: isLoading
                    ? null
                    : () => ref.read(authStateProvider.notifier).signInWithGoogle(
                          role: _role,
                          createProfileIfMissing: true,
                        ),
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
                onPressed: isLoading
                    ? null
                    : () => ref.read(authStateProvider.notifier).signInWithFacebook(
                          role: _role,
                          createProfileIfMissing: true,
                        ),
                icon: const Icon(Icons.facebook, size: 22, color: Colors.white),
                label: const Text('Continue with Facebook'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1877F2),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Already have an account?', style: TextStyle(color: AppTheme.textSecondary)),
                  TextButton(
                    onPressed: isLoading ? null : widget.onSignIn,
                    child: const Text('Sign in'),
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
