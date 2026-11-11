import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'core/services/database_service.dart';
import 'features/navigation/presentation/main_navigation_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Rehydrate cached profiles/settings before the first auth read so mock
  // profiles keep hasCompletedOnboarding across reloads and logouts.
  await DatabaseService.instance.initializeLocalCache();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('[Firebase] Initialized with DefaultFirebaseOptions.');
  } catch (e) {
    debugPrint('[Firebase] Running in local resilient database mode: $e');
  }

  runApp(
    const ProviderScope(
      child: SwipeinnApp(),
    ),
  );
}

class SwipeinnApp extends StatelessWidget {
  const SwipeinnApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Swipeinn',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const MainNavigationShell(),
    );
  }
}
