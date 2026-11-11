import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/user_model.dart';
import 'auth_provider.dart';
import 'auth_ui.dart';
import 'role_selector.dart';

/// Shown when Firebase Auth has a valid session but `users/{uid}` is missing
/// (legacy accounts, interrupted sign-ups, or first-time OAuth sign-ins).
class CompleteProfileScreen extends ConsumerStatefulWidget {
  const CompleteProfileScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<CompleteProfileScreen> createState() =>
      _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends ConsumerState<CompleteProfileScreen> {
  final _nameController = TextEditingController();
  UserRole _role = UserRole.student;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final pending = _pendingProfile();
    if (pending != null && pending.displayName.isNotEmpty) {
      _nameController.text = pending.displayName;
    }
    _initialized = true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  ProfileSetupRequired? _pendingProfile() {
    final error = ref.read(authStateProvider).error;
    return error is ProfileSetupRequired ? error : null;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    await ref.read(authStateProvider.notifier).completeProfile(
          role: _role,
          displayName: _nameController.text.trim(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final pending = _pendingProfile();
    final isLoading = authState.isLoading;
    final error = authState.hasError && authState.error is! ProfileSetupRequired
        ? authState.error
        : null;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Finish your profile'),
        actions: [
          TextButton(
            onPressed: isLoading
                ? null
                : () => ref.read(authStateProvider.notifier).signOut(),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'One last step',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.navyDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                pending == null || pending.email.isEmpty
                    ? 'Choose your role and confirm your name to finish setting up your account.'
                    : 'You are signed in as ${pending.email}. Choose your role and confirm your name to finish setting up your account.',
                style: const TextStyle(color: AppTheme.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 24),
              if (error != null) AuthErrorBanner(message: authErrorMessage(error)),
              RoleSelector(
                selected: _role,
                onChanged: isLoading ? (_) {} : (role) => setState(() => _role = role),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => isLoading ? null : _submit(),
                decoration: InputDecoration(
                  labelText: 'Full name',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: isLoading ? null : _submit,
                child: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.navyDark,
                        ),
                      )
                    : const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
