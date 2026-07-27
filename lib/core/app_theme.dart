// lib/core/app_theme.dart
import 'package:flutter/material.dart';

/// Warm cream + coral palette, matching the mockups in docs/designs/image.png.
class AppColors {
  AppColors._();

  static const cream = Color(0xFFFBF1E4);
  static const surface = Color(0xFFFFFFFF);
  static const coral = Color(0xFFFF6F52);
  static const coralDark = Color(0xFFE85A3D);
  static const textDark = Color(0xFF352E2A);
  static const textMuted = Color(0xFF9A9188);
  static const divider = Color(0xFFEFE7D8);

  static const owedBg = Color(0xFFCBEBD5);
  static const owedText = Color(0xFF1F7A45);
  static const owingBg = Color(0xFFF7C9BC);
  static const owingText = Color(0xFFC0432B);
  static const settledBg = Color(0xFFE7E1D8);
  static const settledText = Color(0xFF6B6259);

  static const avatarPalette = <Color>[
    Color(0xFF7CA8E0),
    Color(0xFFB79AE0),
    Color(0xFFEF9AC0),
    Color(0xFFF4B860),
    Color(0xFF7FC9A9),
    Color(0xFFE58B78),
  ];

  /// Deterministic avatar color from any stable id/name so the same
  /// person/group always renders the same color across the app.
  static Color avatarFor(String seed) {
    final sum = seed.codeUnits.fold<int>(0, (a, b) => a + b);
    return avatarPalette[sum % avatarPalette.length];
  }
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.coral,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.coral,
      surface: AppColors.surface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.cream,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.cream,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.coral,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          elevation: 0,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.coralDark),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.coral,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      textTheme: ThemeData.light().textTheme.apply(
            bodyColor: AppColors.textDark,
            displayColor: AppColors.textDark,
          ),
      dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 1),
    );
  }
}
