import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';

void main() {
  test('light and dark tokens differ and expose the fixed palette', () {
    expect(GlassTokens.dark.gradientBottom, const Color(0xFF0E0F16));
    expect(GlassTokens.light.gradientTop, const Color(0xFFEEF1FA));
    expect(GlassTokens.dark.positive, const Color(0xFF4ADE80));
    expect(GlassTokens.light.positive, const Color(0xFF0E9E6E));
    expect(GlassTokens.dark.brandStart, const Color(0xFF6E8BFF));
    expect(GlassTokens.light.textPrimary, const Color(0xFF1A1C22));
    expect(GlassTokens.dark.blurCard, 18);
    expect(GlassTokens.dark.blurStrong, 24);
  });

  test('lerp returns a GlassTokens', () {
    final mixed = GlassTokens.light.lerp(GlassTokens.dark, 0.5);
    expect(mixed, isA<GlassTokens>());
  });
}
