import 'package:flutter/material.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';

/// Inline colored "+₹420.00" / "-₹150.00" / "Settled" text for a single
/// friend/group/settlement row. balance > 0 means money is owed TO the
/// signed-in user; balance < 0 means the signed-in user owes it.
class BalanceAmount extends StatelessWidget {
  final double balance;
  final TextStyle? style;

  const BalanceAmount({super.key, required this.balance, this.style});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final isOwed = balance > 0.005;
    final isOwing = balance < -0.005;
    final color = isOwed ? t.positive : (isOwing ? t.negative : t.settled);
    final text = isOwed
        ? '+₹${balance.toStringAsFixed(2)}'
        : (isOwing ? '-₹${balance.abs().toStringAsFixed(2)}' : 'Settled');
    return Text(
      text,
      style: (style ?? const TextStyle(fontWeight: FontWeight.w700)).copyWith(color: color),
    );
  }
}
