import 'package:flutter/material.dart';

class AppTheme {
  // Brand Colors (Bumble inspired warm amber & high trust navy)
  static const Color primaryAmber = Color(0xFFFFB800);
  static const Color primaryDarkAmber = Color(0xFFE6A600);
  static const Color navyDark = Color(0xFF111827);
  static const Color surfaceCard = Color(0xFFFFFFFF);
  static const Color backgroundLight = Color(0xFFF9FAFB);
  static const Color textPrimary = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color verifiedBlue = Color(0xFF0284C7);
  static const Color passRed = Color(0xFFEF4444);
  static const Color likeGreen = Color(0xFF10B981);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryAmber,
        primary: primaryAmber,
        secondary: navyDark,
        surface: surfaceCard,
      ),
      scaffoldBackgroundColor: backgroundLight,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: navyDark),
        titleTextStyle: TextStyle(
          color: navyDark,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryAmber,
          foregroundColor: navyDark,
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaceCard,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }
}
