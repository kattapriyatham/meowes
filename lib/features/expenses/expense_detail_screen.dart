// lib/features/expenses/expense_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/async_action.dart';
import 'package:meowes_app/core/format_added.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart'
    show friendRepositoryProvider;
import 'package:meowes_app/models/app_user.dart';
import 'package:meowes_app/models/expense.dart';
import 'package:meowes_app/models/expense_split.dart';
import 'package:meowes_app/repositories/expense_repository.dart';
import 'package:meowes_app/features/expenses/add_expense_screen.dart';
import 'package:meowes_app/features/moderation/report_sheet.dart';

class _ExpenseDetailData {
  final Expense expense;
  final List<ExpenseSplit> splits;
  final Map<String, String> namesById;
  const _ExpenseDetailData({
    required this.expense,
    required this.splits,
    required this.namesById,
  });
}

class ExpenseDetailScreen extends ConsumerWidget {
  final Expense expense;
  const ExpenseDetailScreen({super.key, required this.expense});

  Future<_ExpenseDetailData> _load(WidgetRef ref) async {
    final repo = ref.read(expenseRepositoryProvider);
    final friendRepo = ref.read(friendRepositoryProvider);
    final freshExpense = await repo.getExpenseById(expense.id);
    final splits = await repo.getExpenseSplits(expense.id);
    final participantIds = {
      ...splits.map((s) => s.userId),
      freshExpense.paidBy,
    }.toList();
    final profiles = participantIds.isEmpty
        ? <AppUser>[]
        : await friendRepo.getPublicProfiles(participantIds);
    final namesById = {for (final p in profiles) p.id: p.name};
    return _ExpenseDetailData(
      expense: freshExpense,
      splits: splits,
      namesById: namesById,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(expenseRepositoryProvider);
    ref.watch(dataChangedTickerProvider);
    final t = Theme.of(context).extension<GlassTokens>()!;
    return FutureBuilder<_ExpenseDetailData>(
      future: _load(ref),
      builder: (context, snapshot) {
        final data =
            snapshot.data ??
            _ExpenseDetailData(
              expense: expense,
              splits: const [],
              namesById: const {},
            );
        final current = data.expense;
        final me = ref.watch(supabaseClientProvider).auth.currentUser?.id;
        String nameOf(String id) => data.namesById[id] ?? 'Unknown';
        final payer = current.paidBy == me ? 'You' : nameOf(current.paidBy);

        return DetailHeroScaffold(
          heroAsset: 'assets/images/expense-detail-hero.png',
          heroImageKey: const Key('expense-detail-hero-image'),
          sheetKey: const Key('expense-detail-scroll-sheet'),
          title: current.description,
          actionBuilders: [
            (context) => Material(
              color: Colors.white.withValues(alpha: 0.92),
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Report',
                icon: const Icon(Icons.flag_outlined),
                onPressed: () => showReportSheet(
                  context,
                  ref,
                  targetType: 'expense',
                  targetId: current.id,
                  title: 'Report this expense',
                ),
              ),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '₹${(current.amountMinorUnits / 100).toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Paid by $payer',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: t.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Added ${formatAdded(current.createdAt)}',
                style: TextStyle(fontSize: 13, color: t.textMuted),
              ),
              const SizedBox(height: 4),
              if (current.isEdited)
                Text(
                  'Edited',
                  style: TextStyle(
                    color: t.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const SizedBox(height: 24),
              const SectionHeader(title: 'Split between'),
              const SizedBox(height: 12),
              if (data.splits.isNotEmpty)
                SoftCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < data.splits.length; i++) ...[
                        if (i > 0) Divider(height: 1, color: t.glassBorder),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              AppAvatar(
                                seed: data.splits[i].userId,
                                label: nameOf(data.splits[i].userId),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  nameOf(data.splits[i].userId),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: t.textPrimary,
                                  ),
                                ),
                              ),
                              Text(
                                '₹${(data.splits[i].shareAmountMinorUnits / 100).toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: t.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: PillButton(
                      label: 'Edit',
                      primary: false,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AddExpenseScreen(
                            groupId: current.groupId,
                            participantIds: data.splits
                                .map((s) => s.userId)
                                .toList(),
                            editing: current,
                            existingSplits: data.splits,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PillButton(
                      label: 'Delete',
                      primary: false,
                      onTap: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Delete expense?'),
                            content: Text(
                              '"${data.expense.description}" will be removed for everyone it\'s split with.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true || !context.mounted) return;
                        final ok = await runAction(
                          context,
                          ref,
                          action: () => repo.deleteExpense(expense.id),
                          successMessage: 'Expense deleted',
                        );
                        if (ok && context.mounted) Navigator.of(context).pop();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
