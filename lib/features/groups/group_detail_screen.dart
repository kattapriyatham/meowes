// lib/features/groups/group_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/theme/app_typography.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/expenses/add_expense_screen.dart';
import 'package:meowes_app/features/expenses/expense_detail_screen.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart' show friendRepositoryProvider;
import 'package:meowes_app/features/moderation/report_sheet.dart';
import 'package:meowes_app/features/settlements/settle_up_screen.dart';
import 'package:meowes_app/models/app_user.dart';
import 'package:meowes_app/models/expense.dart';
import 'package:meowes_app/repositories/expense_repository.dart';

class _GroupDetailData {
  final List<String> memberIds;
  final Map<String, String> namesById;
  final List<dynamic> debts;
  const _GroupDetailData({required this.memberIds, required this.namesById, required this.debts});
}

class GroupDetailScreen extends ConsumerWidget {
  final String groupId;
  const GroupDetailScreen({super.key, required this.groupId});

  Future<_GroupDetailData> _load(WidgetRef ref) async {
    final client = ref.read(supabaseClientProvider);
    final friendRepo = ref.read(friendRepositoryProvider);

    final memberRows = await client.from('group_members').select('user_id').eq('group_id', groupId);
    final memberIds = memberRows.map((r) => r['user_id'] as String).toList();

    final debtsRaw = await client.rpc('get_group_debts', params: {'target_group_id': groupId});
    final debts = (debtsRaw as List<dynamic>?) ?? [];

    final profiles = memberIds.isEmpty ? <AppUser>[] : await friendRepo.getPublicProfiles(memberIds);
    final namesById = {for (final p in profiles) p.id: p.name};

    return _GroupDetailData(memberIds: memberIds, namesById: namesById, debts: debts);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(supabaseClientProvider).auth.currentUser!.id;
    final expenseRepo = ref.watch(expenseRepositoryProvider);
    return FutureBuilder<_GroupDetailData>(
      future: _load(ref),
      builder: (context, snapshot) {
        final data = snapshot.data ?? const _GroupDetailData(memberIds: [], namesById: {}, debts: []);
        String nameOf(String id) => data.namesById[id] ?? 'Unknown';
        // Current user first so the Add-expense payer defaults to "me".
        final participantIds = [me, ...data.memberIds.where((id) => id != me)];

        return GlassScaffold(
          appBar: GlassAppBar(
            title: 'Group',
            actions: [
              IconButton(
                tooltip: 'Report',
                icon: const Icon(Icons.flag_outlined),
                onPressed: () => showReportSheet(
                  context,
                  ref,
                  targetType: 'group',
                  targetId: groupId,
                  title: 'Report this group',
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                  children: [
                    AvatarStack(
                      seeds: data.memberIds,
                      labels: [for (final id in data.memberIds) nameOf(id)],
                    ),
                    const SizedBox(height: 20),
                    const SectionHeader(title: 'Expenses'),
                    const SizedBox(height: 12),
                    StreamBuilder<List<Expense>>(
                      stream: expenseRepo.watchExpenses(groupId: groupId),
                      builder: (context, expenseSnapshot) {
                        final expenses = expenseSnapshot.data ?? [];
                        if (expenses.isEmpty) {
                          return const EmptyStateBox(
                            icon: Icons.receipt_long_outlined,
                            message: 'No expenses logged in this group yet.',
                          );
                        }
                        return SoftCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              for (var i = 0; i < expenses.length; i++) ...[
                                if (i > 0) const Divider(height: 1),
                                _ExpenseRow(expense: expenses[i]),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    const SectionHeader(title: 'Smart settle suggestions'),
                    const SizedBox(height: 12),
                    if (data.debts.isEmpty)
                      const EmptyStateBox(
                        icon: Icons.celebration_outlined,
                        message: 'Everyone is settled up.',
                      )
                    else
                      SoftCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (var i = 0; i < data.debts.length; i++) ...[
                              if (i > 0) const Divider(height: 1),
                              _DebtRow(
                                debt: data.debts[i],
                                me: me,
                                groupId: groupId,
                                nameOf: nameOf,
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
                if (data.memberIds.isNotEmpty)
                  Positioned(
                    right: 0,
                    bottom: 16,
                    child: FloatingActionButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AddExpenseScreen(
                            groupId: groupId,
                            participantIds: participantIds,
                          ),
                        ),
                      ),
                      child: const Icon(Icons.add),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  final Expense expense;
  const _ExpenseRow({required this.expense});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ExpenseDetailScreen(expense: expense)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  expense.description,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: t.textPrimary),
                ),
              ),
              Text(
                '₹${(expense.amountMinorUnits / 100).toStringAsFixed(2)}',
                style: moneyStyle(t.textPrimary, size: 14).copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DebtRow extends StatelessWidget {
  final dynamic debt;
  final String me;
  final String groupId;
  final String Function(String) nameOf;
  const _DebtRow({required this.debt, required this.me, required this.groupId, required this.nameOf});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    // markPaid always records from_user = me, so only the actual debtor's
    // own row should be tappable into settle-up — otherwise a member could
    // record a settlement in their own name for someone else's debt.
    final onTap = debt['from_user'] == me
        ? () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SettleUpScreen(
                  toUser: debt['to_user'] as String,
                  amountMinorUnits: (double.parse(debt['amount'].toString()) * 100).round(),
                  groupId: groupId,
                  toUserName: nameOf(debt['to_user'] as String),
                ),
              ),
            )
        : null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${nameOf(debt['from_user'] as String)} owes ${nameOf(debt['to_user'] as String)}',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: t.textPrimary),
                ),
              ),
              Text(
                '₹${double.parse(debt['amount'].toString()).toStringAsFixed(2)}',
                style: moneyStyle(t.negative, size: 14).copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
