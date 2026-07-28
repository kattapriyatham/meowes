// lib/features/friends/friend_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/expenses/add_expense_screen.dart';
import 'package:meowes_app/features/expenses/expense_detail_screen.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart';
import 'package:meowes_app/features/groups/group_detail_screen.dart';
import 'package:meowes_app/features/settlements/settle_up_screen.dart';
import 'package:meowes_app/models/friend_activity_item.dart';
import 'package:meowes_app/repositories/expense_repository.dart';

class _FriendDetailData {
  final String? name;
  final double balance;
  const _FriendDetailData({required this.name, required this.balance});
}

class FriendDetailScreen extends ConsumerWidget {
  final String friendUserId;
  const FriendDetailScreen({super.key, required this.friendUserId});

  Future<_FriendDetailData> _load(WidgetRef ref) async {
    final client = ref.read(supabaseClientProvider);
    final friendRepo = ref.read(friendRepositoryProvider);
    final me = client.auth.currentUser!.id;
    final profiles = await friendRepo.getPublicProfiles([friendUserId]);
    final balance = ((await client.rpc('get_friend_balance', params: {
      'user_a': me,
      'user_b': friendUserId,
    })) as num?)?.toDouble() ?? 0;
    return _FriendDetailData(
      name: profiles.isNotEmpty ? profiles.first.name : null,
      balance: balance,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    final me = client.auth.currentUser!.id;
    return FutureBuilder<_FriendDetailData>(
      future: _load(ref),
      builder: (context, snapshot) {
        final data = snapshot.data ?? const _FriendDetailData(name: null, balance: 0);
        final balance = data.balance;
        // get_friend_balance(me, friend) is positive when the friend owes
        // me, negative when I owe the friend. Settling here means "I paid
        // this" (markPaid always records from_user = me), so the button
        // only makes sense when I'm the one who owes — offering it when
        // the friend owes me would record a payment in the wrong direction.
        final iOwe = balance < -0.005;
        return GlassScaffold(
          appBar: GlassAppBar(title: data.name ?? 'Friend'),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                BalanceSummaryCard(balance: balance),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: PillButton(
                        label: 'Add expense',
                        primary: true,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AddExpenseScreen(
                              participantIds: [me, friendUserId],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (iOwe) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: PillButton(
                          label: 'Settle up',
                          primary: false,
                          onTap: () => Navigator.of(context).push(
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
            ),
          ),
        );
      },
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
    final t = Theme.of(context).extension<GlassTokens>()!;
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
                  )
                else
                  SoftCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < visible.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          _ActivityRow(
                            item: visible[i],
                            icon: _iconFor(visible[i].kind),
                            onTap: visible[i].kind == FriendActivityKind.settlement
                                ? null
                                : () => _openItem(context, visible[i]),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (hasSettled)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Align(
                      alignment: Alignment.center,
                      child: TextButton(
                        onPressed: () => setState(() => _showSettled = !_showSettled),
                        child: Text(
                          _showSettled ? 'Hide settled' : 'Show settled',
                          style: TextStyle(color: t.textSecondary, fontWeight: FontWeight.w600),
                        ),
                      ),
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

class _ActivityRow extends StatelessWidget {
  final FriendActivityItem item;
  final IconData icon;
  final VoidCallback? onTap;
  const _ActivityRow({required this.item, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: t.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.name,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: t.textPrimary),
                ),
              ),
              BalanceAmount(balance: item.net),
            ],
          ),
        ),
      ),
    );
  }
}
