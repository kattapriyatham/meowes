import 'package:flutter/material.dart';
import 'package:meowes_app/core/app_theme.dart';

/// Full-width tinted card: "You are owed"/"You owe"/"All settled up" plus
/// the amount. Used for Home's overall summary and Friend Detail's balance.
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
    final isOwed = balance > 0.005;
    final isOwing = balance < -0.005;
    final bg = isOwed ? AppColors.owedBg : (isOwing ? AppColors.owingBg : AppColors.settledBg);
    final fg = isOwed ? AppColors.owedText : (isOwing ? AppColors.owingText : AppColors.settledText);
    final label = isOwed ? 'You are owed' : (isOwing ? 'You owe' : settledMessage);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 6),
          if (loading)
            SizedBox(
              height: 30,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: fg),
            )
          else if (!isOwed && !isOwing)
            const Text('🐾', style: TextStyle(fontSize: 26))
          else
            Text(
              '₹${balance.abs().toStringAsFixed(2)}',
              style: TextStyle(color: fg, fontSize: 30, fontWeight: FontWeight.w800),
            ),
        ],
      ),
    );
  }
}
