import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowes_app/core/theme/app_typography.dart';

void main() {
  testWidgets('money style is tabular and colored', (WidgetTester tester) async {
    final s = moneyStyle(const Color(0xFF4ADE80), size: 20);
    expect(s.color, const Color(0xFF4ADE80));
    expect(s.fontFeatures, contains(const FontFeature.tabularFigures()));
    expect(s.fontSize, 20);
  });

  testWidgets('text theme applies the primary color to body', (WidgetTester tester) async {
    final t = buildTextTheme(const Color(0xFF1A1C22));
    expect(t.bodyMedium!.color, const Color(0xFF1A1C22));
  });
}
