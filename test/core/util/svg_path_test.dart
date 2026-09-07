import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowes_app/core/util/svg_path.dart';

void main() {
  group('parseSvgPath', () {
    test('absolute move + line + close forms the expected bounds', () {
      final p = parseSvgPath('M0 0 L10 0 L10 10 Z');
      expect(p.getBounds(), const Rect.fromLTRB(0, 0, 10, 10));
    });

    test('relative commands accumulate from the current point', () {
      final p = parseSvgPath('M5 5 l5 0 l0 5 z');
      expect(p.getBounds(), const Rect.fromLTRB(5, 5, 10, 10));
    });

    test('H/V and implicit line-tos after M', () {
      final p = parseSvgPath('M0 0 2 0 H4 V4');
      expect(p.getBounds(), const Rect.fromLTRB(0, 0, 4, 4));
    });

    test('tight number packing: "-.26.13" tokenizes as two numbers', () {
      final p = parseSvgPath('M0 0 l-.26.13');
      final b = p.getBounds();
      expect(b.left, closeTo(-0.26, 1e-6));
      expect(b.bottom, closeTo(0.13, 1e-6));
    });

    test('the Google "G" blue segment parses to a plausible box', () {
      final p = parseSvgPath(
        'M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 '
        '2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z',
      );
      final b = p.getBounds();
      expect(b.left, closeTo(12, 0.01));
      expect(b.right, closeTo(22.56, 0.5));
      expect(b.width, greaterThan(8));
      expect(b.height, greaterThan(8));
    });
  });
}
