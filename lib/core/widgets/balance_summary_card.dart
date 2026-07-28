import 'package:flutter/material.dart';
import 'package:meowes_app/core/theme/app_typography.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/soft_card.dart';

/// Full-width balance summary: "You are owed"/"You owe"/"All settled up" plus
/// the amount, in the paper (SoftCard) style with token colors.
class BalanceSummaryCard extends StatelessWidget {
  final double balance;
  final bool loading;
  final String settledMessage;

  const BalanceSummaryCard({
    super.key,
    required this.balance,
    this.loading = false,
    this.settledMessage = 'All settled up',
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final isOwed = balance > 0.005;
    final isOwing = balance < -0.005;
    final color = isOwed ? t.positive : (isOwing ? t.negative : t.settled);
    final label = isOwed ? 'You are owed' : (isOwing ? 'You owe' : settledMessage);

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: t.textSecondary, fontWeight: FontWeight.w500, fontSize: 14)),
          const SizedBox(height: 8),
          if (loading)
            const SizedBox(height: 30, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
          else if (!isOwed && !isOwing)
            Text(settledMessage, style: TextStyle(color: t.settled, fontSize: 18, fontWeight: FontWeight.w700))
          else
            Text('₹${balance.abs().toStringAsFixed(2)}', style: moneyStyle(color, size: 32)),
        ],
      ),
    );
  }
}
