import 'package:flutter/material.dart';

/// Inline "🪙 +15" / "🪙 120" coin amount. Fixed warm-gold icon+color so
/// in-app coin currency reads distinctly from real-money amounts (see
/// [BalanceAmount]) — a purchase or reward is never mistaken for a rupee
/// figure at a glance.
class CoinAmount extends StatelessWidget {
  final int amount;

  /// Prefixes a `+` for a positive amount (negative already renders its
  /// own `-` via [amount]'s toString). Used for "earned" contexts like a
  /// reward chip, where a bare number would read ambiguously.
  final bool showSign;

  final double iconSize;
  final TextStyle? style;

  const CoinAmount({
    super.key,
    required this.amount,
    this.showSign = false,
    this.iconSize = 16,
    this.style,
  });

  static const gold = Color(0xFFC08A2E);

  @override
  Widget build(BuildContext context) {
    final text = (showSign && amount >= 0) ? '+$amount' : '$amount';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.pets, size: iconSize, color: gold),
        const SizedBox(width: 4),
        Text(
          text,
          style: (style ?? const TextStyle(fontWeight: FontWeight.w700)).copyWith(color: gold),
        ),
      ],
    );
  }
}
