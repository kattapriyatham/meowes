import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// User's theme preference. Defaults to following the OS setting; the
/// Profile screen lets the user cycle through System -> Light -> Dark.
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

ThemeMode nextThemeMode(ThemeMode current) {
  switch (current) {
    case ThemeMode.system:
      return ThemeMode.light;
    case ThemeMode.light:
      return ThemeMode.dark;
    case ThemeMode.dark:
      return ThemeMode.system;
  }
}

String themeModeLabel(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.system:
      return 'System';
    case ThemeMode.light:
      return 'Light';
    case ThemeMode.dark:
      return 'Dark';
  }
}
