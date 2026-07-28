// lib/features/friends/friend_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/expenses/add_expense_screen.dart';
import 'package:meowes_app/features/expenses/expense_detail_screen.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart';
import 'package:meowes_app/features/groups/group_detail_screen.dart';
import 'package:meowes_app/features/settlements/settle_up_screen.dart';
import 'package:meowes_app/models/app_user.dart';
import 'package:meowes_app/models/friend_activity_item.dart';
import 'package:meowes_app/repositories/expense_repository.dart';

class FriendDetailScreen extends ConsumerWidget {
  final String friendUserId;
  const FriendDetailScreen({super.key, required this.friendUserId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    final friendRepo = ref.watch(friendRepositoryProvider);
    final me = client.auth.currentUser!.id;
    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder<List<AppUser>>(
          future: friendRepo.getPublicProfiles([friendUserId]),
          builder: (context, snapshot) {
            final name = snapshot.data?.isNotEmpty == true ? snapshot.data!.first.name : null;
            return Text(name ?? 'Friend');
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: FutureBuilder(
          future: client.rpc('get_friend_balance', params: {
            'user_a': me,
            'user_b': friendUserId,
          }),
          builder: (context, snapshot) {
            final balance = (snapshot.data as num?)?.toDouble() ?? 0;
            // get_friend_balance(me, friend) is positive when the friend owes
            // me, negative when I owe the friend. Settling here means "I paid
            // this" (markPaid always records from_user = me), so the button
            // only makes sense when I'm the one who owes — offering it when
            // the friend owes me would record a payment in the wrong direction.
            final iOwe = balance < -0.005;
            return ListView(
              children: [
                BalanceSummaryCard(balance: balance),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AddExpenseScreen(
                              participantIds: [me, friendUserId],
                            ),
                          ),
                        ),
                        child: const Text('Add Expense'),
                      ),
                    ),
                    if (iOwe) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppOutlinedButton(
                          label: 'Settle Up',
                          color: AppColors.coral,
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SettleUpScreen(
                                toUser: friendUserId,
                                amountMinorUnits: (balance.abs() * 100).round(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 24),
                _FriendActivitySection(friendUserId: friendUserId),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The activity list under the balance card. A stateful widget so it can
/// hold the "show settled" toggle. Each row is a direct expense, a shared
/// group (by name), or a payment; the amount shown is the caller's net for
/// that row (get_friend_activity's sign convention), so the visible rows
/// reconcile to the balance card above.
class _FriendActivitySection extends ConsumerStatefulWidget {
  final String friendUserId;
  const _FriendActivitySection({required this.friendUserId});

  @override
  ConsumerState<_FriendActivitySection> createState() => _FriendActivitySectionState();
}

class _FriendActivitySectionState extends ConsumerState<_FriendActivitySection> {
  bool _showSettled = false;

  bool _isSettled(FriendActivityItem i) => i.net.abs() < 0.005;

  Future<void> _openItem(BuildContext context, FriendActivityItem item) async {
    switch (item.kind) {
      case FriendActivityKind.group:
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => GroupDetailScreen(groupId: item.refId),
        ));
        break;
      case FriendActivityKind.expense:
        final expense = await ref.read(expenseRepositoryProvider).getExpenseById(item.refId);
        if (!context.mounted) return;
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ExpenseDetailScreen(expense: expense),
        ));
        break;
      case FriendActivityKind.settlement:
        break; // no detail screen for settlements
    }
  }

  IconData _iconFor(FriendActivityKind kind) {
    switch (kind) {
      case FriendActivityKind.group:
        return Icons.groups;
      case FriendActivityKind.settlement:
        return Icons.swap_horiz;
      case FriendActivityKind.expense:
        return Icons.receipt_long_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final expenseRepo = ref.watch(expenseRepositoryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Activity'),
        const SizedBox(height: 12),
        FutureBuilder<List<FriendActivityItem>>(
          future: expenseRepo.getFriendActivity(widget.friendUserId),
          builder: (context, snapshot) {
            final all = snapshot.data ?? [];
            final hasSettled = all.any(_isSettled);
            final visible = _showSettled ? all : all.where((i) => !_isSettled(i)).toList();

            if (all.isEmpty) {
              return const EmptyStateBox(
                icon: Icons.receipt_long_outlined,
                message: 'No activity with this friend yet.',
              );
            }
            return Column(
              children: [
                if (visible.isEmpty)
                  const EmptyStateBox(
                    icon: Icons.check_circle_outline,
                    message: 'All settled with this friend.',
                  ),
                for (final item in visible) ...[
                  AppCard(
                    onTap: item.kind == FriendActivityKind.settlement
                        ? null
                        : () => _openItem(context, item),
                    child: Row(
                      children: [
                        Icon(_iconFor(item.kind), color: AppColors.coral),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            item.name,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ),
                        BalanceAmount(balance: item.net),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (hasSettled)
                  Align(
                    alignment: Alignment.center,
                    child: TextButton(
                      onPressed: () => setState(() => _showSettled = !_showSettled),
                      child: Text(_showSettled ? 'Hide settled' : 'Show settled'),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
