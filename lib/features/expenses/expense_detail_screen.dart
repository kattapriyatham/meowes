// lib/features/expenses/expense_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart' show friendRepositoryProvider;
import 'package:meowes_app/models/app_user.dart';
import 'package:meowes_app/models/expense.dart';
import 'package:meowes_app/models/expense_split.dart';
import 'package:meowes_app/repositories/expense_repository.dart';
import 'package:meowes_app/features/expenses/add_expense_screen.dart';

class _ExpenseDetailData {
  final List<ExpenseSplit> splits;
  final Map<String, String> namesById;
  const _ExpenseDetailData({required this.splits, required this.namesById});
}

class ExpenseDetailScreen extends ConsumerWidget {
  final Expense expense;
  const ExpenseDetailScreen({super.key, required this.expense});

  Future<_ExpenseDetailData> _load(WidgetRef ref) async {
    final repo = ref.read(expenseRepositoryProvider);
    final friendRepo = ref.read(friendRepositoryProvider);
    final splits = await repo.getExpenseSplits(expense.id);
    final participantIds = splits.map((s) => s.userId).toList();
    final profiles =
        participantIds.isEmpty ? <AppUser>[] : await friendRepo.getPublicProfiles(participantIds);
    final namesById = {for (final p in profiles) p.id: p.name};
    return _ExpenseDetailData(splits: splits, namesById: namesById);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(expenseRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(expense.description)),
      body: FutureBuilder<_ExpenseDetailData>(
        future: _load(ref),
        builder: (context, snapshot) {
          final data = snapshot.data ?? const _ExpenseDetailData(splits: [], namesById: {});
          String nameOf(String id) => data.namesById[id] ?? 'Unknown';

          return Padding(
            padding: const EdgeInsets.all(20),
            child: ListView(
              children: [
                Text(
                  '₹${(expense.amountMinorUnits / 100).toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                if (expense.isEdited)
                  const Text('Edited', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                const SizedBox(height: 24),
                const SectionHeader(title: 'Split between'),
                const SizedBox(height: 12),
                for (final s in data.splits) ...[
                  AppCard(
                    child: Row(
                      children: [
                        AppAvatar(seed: s.userId, label: nameOf(s.userId)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(nameOf(s.userId), style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        Text(
                          '₹${(s.shareAmountMinorUnits / 100).toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: AppOutlinedButton(
                        label: 'Edit',
                        color: AppColors.coral,
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AddExpenseScreen(
                              groupId: expense.groupId,
                              participantIds: data.splits.map((s) => s.userId).toList(),
                              editing: expense,
                              existingSplits: data.splits,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppOutlinedButton(
                        label: 'Delete',
                        color: AppColors.owingText,
                        onPressed: () async {
                          await repo.deleteExpense(expense.id);
                          if (context.mounted) Navigator.of(context).pop();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
