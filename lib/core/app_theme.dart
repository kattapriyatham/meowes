// lib/core/app_theme.dart
import 'package:flutter/material.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/theme/app_typography.dart';

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

  static ThemeData _base(Brightness brightness, GlassTokens tokens) {
    final scheme = ColorScheme.fromSeed(
      seedColor: tokens.brandSolid,
      brightness: brightness,
    ).copyWith(primary: tokens.brandSolid);
    final radius = BorderRadius.circular(16);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: buildTextTheme(tokens.textPrimary),
      extensions: [tokens],
      iconTheme: IconThemeData(color: tokens.textPrimary),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      dividerTheme: DividerThemeData(color: tokens.textPrimary.withValues(alpha: 0.06), thickness: 1),
      cardTheme: CardThemeData(
        color: tokens.cardColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tokens.cardColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      listTileTheme: ListTileThemeData(iconColor: tokens.textPrimary, textColor: tokens.textPrimary),
      // Cream "paper" form fields.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.cardColor,
        hintStyle: TextStyle(color: tokens.textMuted),
        labelStyle: TextStyle(color: tokens.textSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: tokens.textPrimary.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: tokens.brandSolid, width: 1.5),
        ),
      ),
      // Ink pill buttons (match the Home primary action).
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: tokens.brandSolid,
          foregroundColor: tokens.onBrand,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: tokens.brandSolid),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: tokens.brandSolid,
        foregroundColor: tokens.onBrand,
        elevation: 0,
      ),
    );
  }

  static ThemeData get light => _base(Brightness.light, GlassTokens.light);
  static ThemeData get dark => _base(Brightness.dark, GlassTokens.dark);
}
