// lib/features/groups/group_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/expenses/expense_detail_screen.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart' show friendRepositoryProvider;
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
    return Scaffold(
      appBar: AppBar(title: const Text('Group')),
      body: FutureBuilder<_GroupDetailData>(
        future: _load(ref),
        builder: (context, snapshot) {
          final data = snapshot.data ?? const _GroupDetailData(memberIds: [], namesById: {}, debts: []);
          String nameOf(String id) => data.namesById[id] ?? 'Unknown';

          return ListView(
            padding: const EdgeInsets.all(20),
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
                  return Column(
                    children: [
                      for (final e in expenses) ...[
                        AppCard(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => ExpenseDetailScreen(expense: e)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  e.description,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                ),
                              ),
                              Text(
                                '₹${(e.amountMinorUnits / 100).toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
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
                Column(
                  children: [
                    for (final d in data.debts) ...[
                      AppCard(
                        // markPaid always records from_user = me, so only the
                        // actual debtor's own row should be tappable into
                        // settle-up — otherwise a member could record a
                        // settlement in their own name for someone else's debt.
                        onTap: d['from_user'] == me
                            ? () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => SettleUpScreen(
                                      toUser: d['to_user'] as String,
                                      amountMinorUnits:
                                          (double.parse(d['amount'].toString()) * 100).round(),
                                      groupId: groupId,
                                    ),
                                  ),
                                )
                            : null,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${nameOf(d['from_user'] as String)} owes ${nameOf(d['to_user'] as String)}',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                            ),
                            Text(
                              '₹${double.parse(d['amount'].toString()).toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.owingText),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
