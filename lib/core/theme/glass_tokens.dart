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
    required this.cardColor,
    required this.cardShadow,
    required this.blurCard,
    required this.blurStrong,
  });

  final Color gradientTop, gradientBottom, blobIndigo, blobTeal;
  final Color glassFill, glassBorder, glassSheen, glassStrongFill, glassStrongBorder, solidFallback;
  final Color textPrimary, textSecondary, textMuted;
  final Color positive, positiveTint, negative, negativeTint, settled, settledTint;
  final Color brandStart, brandEnd, brandSolid, onBrand;
  // Soft (non-glass) card style used by the warm "paper" theme.
  final Color cardColor, cardShadow;
  final double blurCard, blurStrong;

  LinearGradient get brandGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [brandStart, brandEnd],
      );

  static const dark = GlassTokens(
    gradientTop: Color(0xFF262019), // warm espresso paper
    gradientBottom: Color(0xFF17130F),
    blobIndigo: Color(0x00000000), // paper theme: no ambient blobs
    blobTeal: Color(0x00000000),
    glassFill: Color(0xF22B241D), // near-opaque warm dark card
    glassBorder: Color(0x1FFFFFFF),
    glassSheen: Color(0x00FFFFFF),
    glassStrongFill: Color(0xF7302820),
    glassStrongBorder: Color(0x24FFFFFF),
    solidFallback: Color(0xFF2B241D),
    textPrimary: Color(0xFFF3ECE1),
    textSecondary: Color(0xFFB4A89A),
    textMuted: Color(0xFF867B6D),
    positive: Color(0xFF4ADE80),
    positiveTint: Color(0x294ADE80),
    negative: Color(0xFFFF6B6B),
    negativeTint: Color(0x29FF6B6B),
    settled: Color(0xFF9BA0AA),
    settledTint: Color(0x14FFFFFF),
    brandStart: Color(0xFFF3ECE1), // light "ink" button on dark
    brandEnd: Color(0xFFF3ECE1),
    brandSolid: Color(0xFFF3ECE1),
    onBrand: Color(0xFF17130F),
    cardColor: Color(0xFF2B241D), // warm dark card
    cardShadow: Color(0x66000000),
    blurCard: 18,
    blurStrong: 24,
  );

  static const light = GlassTokens(
    gradientTop: Color(0xFFF0E9DC), // warm cream paper
    gradientBottom: Color(0xFFE8DFCF),
    blobIndigo: Color(0x00000000), // paper theme: no ambient blobs
    blobTeal: Color(0x00000000),
    glassFill: Color(0xF2F6F1E9), // near-opaque cream card
    glassBorder: Color(0x14000000),
    glassSheen: Color(0x00FFFFFF),
    glassStrongFill: Color(0xF7F7F2EA),
    glassStrongBorder: Color(0x14000000),
    solidFallback: Color(0xFFF6F1E9),
    textPrimary: Color(0xFF211E1A), // warm near-black ink
    textSecondary: Color(0xFF8A8175),
    textMuted: Color(0xFFA99F91),
    positive: Color(0xFF2E9E5B), // green
    positiveTint: Color(0x242E9E5B),
    negative: Color(0xFFD64B47), // red
    negativeTint: Color(0x24D64B47),
    settled: Color(0xFF9C8E82),
    settledTint: Color(0x0F000000),
    brandStart: Color(0xFF211E1A), // black ink button
    brandEnd: Color(0xFF211E1A),
    brandSolid: Color(0xFF211E1A),
    onBrand: Color(0xFFF6F1E9),
    cardColor: Color(0xFFF6F1E9), // warm cream card
    cardShadow: Color(0x1A6B5B45), // soft warm shadow
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
