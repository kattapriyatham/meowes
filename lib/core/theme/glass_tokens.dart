import 'package:flutter/material.dart';

@immutable
class GlassTokens extends ThemeExtension<GlassTokens> {
  const GlassTokens({
    required this.gradientTop,
    required this.gradientBottom,
    required this.blobIndigo,
    required this.blobTeal,
    required this.glassFill,
    required this.glassBorder,
    required this.glassSheen,
    required this.glassStrongFill,
    required this.glassStrongBorder,
    required this.solidFallback,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.positive,
    required this.positiveTint,
    required this.negative,
    required this.negativeTint,
    required this.settled,
    required this.settledTint,
    required this.brandStart,
    required this.brandEnd,
    required this.brandSolid,
    required this.onBrand,
    required this.blurCard,
    required this.blurStrong,
  });

  final Color gradientTop, gradientBottom, blobIndigo, blobTeal;
  final Color glassFill, glassBorder, glassSheen, glassStrongFill, glassStrongBorder, solidFallback;
  final Color textPrimary, textSecondary, textMuted;
  final Color positive, positiveTint, negative, negativeTint, settled, settledTint;
  final Color brandStart, brandEnd, brandSolid, onBrand;
  final double blurCard, blurStrong;

  LinearGradient get brandGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [brandStart, brandEnd],
      );

  static const dark = GlassTokens(
    gradientTop: Color(0xFF1E2233),
    gradientBottom: Color(0xFF0E0F16),
    blobIndigo: Color(0x525B7CFA), // #5B7CFA @ 32%
    blobTeal: Color(0x3322B8A6), // #22B8A6 @ 20%
    glassFill: Color(0x12FFFFFF), // white @ 7%
    glassBorder: Color(0x24FFFFFF), // white @ 14%
    glassSheen: Color(0x33FFFFFF), // white @ 20%
    glassStrongFill: Color(0x1AFFFFFF), // white @ 10%
    glassStrongBorder: Color(0x2EFFFFFF), // white @ 18%
    solidFallback: Color(0xFF1A1E2B),
    textPrimary: Color(0xFFF5F6F8),
    textSecondary: Color(0x99FFFFFF),
    textMuted: Color(0x6BFFFFFF),
    positive: Color(0xFF4ADE80),
    positiveTint: Color(0x294ADE80),
    negative: Color(0xFFFF7A7D),
    negativeTint: Color(0x29FF7A7D),
    settled: Color(0xFF9BA0AA),
    settledTint: Color(0x14FFFFFF),
    brandStart: Color(0xFF6E8BFF),
    brandEnd: Color(0xFF5B7CFA),
    brandSolid: Color(0xFF5B7CFA),
    onBrand: Color(0xFFFFFFFF),
    blurCard: 18,
    blurStrong: 24,
  );

  static const light = GlassTokens(
    gradientTop: Color(0xFFEEF1FA),
    gradientBottom: Color(0xFFE3E8F4),
    blobIndigo: Color(0x618FA6FF), // #8FA6FF @ 38%
    blobTeal: Color(0x4D7FE0D0), // #7FE0D0 @ 30%
    glassFill: Color(0x8CFFFFFF), // white @ 55%
    glassBorder: Color(0xB3FFFFFF), // white @ 70%
    glassSheen: Color(0x40FFFFFF), // white @ 25% (subtle thin top highlight)
    glassStrongFill: Color(0x99FFFFFF), // white @ 60%
    glassStrongBorder: Color(0xBFFFFFFF), // white @ 75%
    solidFallback: Color(0xFFF3F5FB),
    textPrimary: Color(0xFF1A1C22),
    textSecondary: Color(0xFF5A5F6B),
    textMuted: Color(0xFF8A8F9C),
    positive: Color(0xFF0E9E6E),
    positiveTint: Color(0x240E9E6E),
    negative: Color(0xFFE5484D),
    negativeTint: Color(0x24E5484D),
    settled: Color(0xFF8A8F9C),
    settledTint: Color(0x0F000000),
    brandStart: Color(0xFF6E8BFF),
    brandEnd: Color(0xFF5B7CFA),
    brandSolid: Color(0xFF5B7CFA),
    onBrand: Color(0xFFFFFFFF),
    blurCard: 18,
    blurStrong: 24,
  );

  // The two token sets are fixed const instances; the app never mutates or
  // animates between them, so copyWith is identity and lerp snaps at the
  // midpoint. This is a deliberate, documented choice, not an omission.
  @override
  GlassTokens copyWith() => this;

  @override
  GlassTokens lerp(ThemeExtension<GlassTokens>? other, double t) {
    if (other is! GlassTokens) return this;
    return t < 0.5 ? this : other;
  }
}
