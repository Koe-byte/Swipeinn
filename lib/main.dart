import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/supabase_config.dart';
import 'core/navigation/app_router.dart';
import 'core/services/database_service.dart';
import 'core/theme/app_theme.dart';
import 'features/navigation/presentation/main_navigation_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseService.instance.initializeLocalCache();

  String? startupError;
  try {
    SupabaseConfig.assertConfigured();
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
    debugPrint('[Supabase] Initialized ${SupabaseConfig.url}');
    // Replay anything that failed while the device was offline last session.
    unawaited(DatabaseService.instance.flushPendingWrites());
  } catch (error) {
    // There is no offline substitute for sign-in: surface the failure instead
    // of pretending the app is usable.
    startupError = error.toString();
    debugPrint('[Supabase] Initialization failed: $error');
  }

  runApp(
    ProviderScope(
      child: SwipeinnApp(startupError: startupError),
    ),
  );
}

class SwipeinnApp extends StatelessWidget {
  final String? startupError;

  const SwipeinnApp({Key? key, this.startupError}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Swipeinn',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      onGenerateRoute: AppRouter.onGenerateRoute,
      home: startupError == null
          ? const MainNavigationShell()
          : _StartupFailureScreen(details: startupError!),
    );
  }
}

class _StartupFailureScreen extends StatelessWidget {
  final String details;

  const _StartupFailureScreen({required this.details});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Swipeinn could not start',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'The app could not connect to Supabase. Check your connection, then reopen the app.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              Text(
                details,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 11, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
