import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'features/navigation/presentation/main_navigation_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      child: RentlyApp(),
    ),
  );
}

class RentlyApp extends StatelessWidget {
  const RentlyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rently',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const MainNavigationShell(),
    );
  }
}
