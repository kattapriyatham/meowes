// lib/features/expenses/expense_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/models/expense.dart';
import 'package:meowes_app/repositories/expense_repository.dart';
import 'package:meowes_app/features/expenses/add_expense_screen.dart';

class ExpenseDetailScreen extends ConsumerWidget {
  final Expense expense;
  const ExpenseDetailScreen({super.key, required this.expense});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(expenseRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(expense.description)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '₹${(expense.amountMinorUnits / 100).toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            if (expense.isEdited)
              const Text('Edited', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AddExpenseScreen(
                          groupId: expense.groupId,
                          participantIds: const [], // populated from expense_splits when wired to a live expense
                        ),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.coral,
                      side: const BorderSide(color: AppColors.coral),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                    child: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await repo.deleteExpense(expense.id);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.owingText,
                      side: const BorderSide(color: AppColors.owingText),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                    child: const Text('Delete'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
