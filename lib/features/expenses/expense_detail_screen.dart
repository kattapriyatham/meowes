import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('₹${(expense.amountMinorUnits / 100).toStringAsFixed(2)}'),
                if (expense.isEdited) const Text('Edited'),
              ],
            ),
          ),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AddExpenseScreen(
                      groupId: expense.groupId,
                      participantIds: const [], // populated from expense_splits when wired to a live expense
                    ),
                  ),
                ),
                child: const Text('Edit'),
              ),
              TextButton(
                onPressed: () async {
                  await repo.deleteExpense(expense.id);
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
