import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';

void main() {
  // GoogleFonts requires an initialized Flutter binding for async font
  // loading (see test/core/theme/app_typography_test.dart), so these use
  // testWidgets rather than the brief's plain test().
  testWidgets('light and dark themes carry their GlassTokens', (WidgetTester tester) async {
    expect(AppTheme.light.extension<GlassTokens>(), GlassTokens.light);
    expect(AppTheme.dark.extension<GlassTokens>(), GlassTokens.dark);
  });

  testWidgets('scaffold background is transparent so GlassBackground shows through', (WidgetTester tester) async {
    expect(AppTheme.light.scaffoldBackgroundColor, Colors.transparent);
    expect(AppTheme.dark.scaffoldBackgroundColor, Colors.transparent);
  });
}
