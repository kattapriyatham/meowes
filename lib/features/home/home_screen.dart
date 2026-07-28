// lib/features/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/expenses/add_expense_screen.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart';
import 'package:meowes_app/features/groups/create_group_screen.dart';
import 'package:meowes_app/features/notifications/notifications_screen.dart';
import 'package:meowes_app/models/app_user.dart';
import 'package:meowes_app/models/friendship.dart';

/// Home tab: a quick overview (greeting + overall-balance hero + primary
/// actions). The full friends/groups lists that used to live here now live
/// in their own tabs (see FriendsScreen/GroupsScreen); this screen keeps
/// only the balance summation logic that used to live in
/// `_FriendsAndSummary` (sum of `get_friend_balance` across accepted
/// friends).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    final friendRepo = ref.watch(friendRepositoryProvider);
    final me = client.auth.currentUser!.id;

    return FutureBuilder<AppUser?>(
      future: friendRepo.getMyProfile(),
      builder: (context, profileSnapshot) {
        final name = profileSnapshot.data?.name;
        final greeting = name != null ? 'Hi $name!' : 'Hi there!';

        return GlassScaffold(
          appBar: GlassAppBar(
            title: greeting,
            actions: [
              IconButton(
                tooltip: 'Notifications',
                icon: const Icon(Icons.notifications_none),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
              children: [
                StreamBuilder<List<Friendship>>(
                  stream: friendRepo.watchFriendships(),
                  builder: (context, snapshot) {
                    final friendIds = (snapshot.data ?? [])
                        .where((f) => f.status == FriendshipStatus.accepted)
                        .map((f) => f.userIdA == me ? f.userIdB : f.userIdA)
                        .toList();
                    return _OverviewBody(
                      me: me,
                      friendIds: friendIds,
                      client: client,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Opens the "add" sheet (add a friend / create a group). Also used as the
/// generic entry point for the Home "Settle up" action, since settling up
/// with a specific person requires picking that person first — there is no
/// standalone "settle" screen to deep-link into from an overview.
void _showAddMenu(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.cream,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.settledBg,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.person_add_alt, color: AppColors.coral),
            title: const Text('Add a friend'),
            onTap: () {
              Navigator.pop(sheetContext);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AddFriendScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.group_add, color: AppColors.coral),
            title: const Text('Create a group'),
            onTap: () {
              Navigator.pop(sheetContext);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
              );
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}

class _OverviewBody extends StatelessWidget {
  final String me;
  final List<String> friendIds;
  final SupabaseClient client;

  const _OverviewBody({
    required this.me,
    required this.friendIds,
    required this.client,
  });

  Future<double> _loadTotalBalance() async {
    if (friendIds.isEmpty) return 0;
    final balances = await Future.wait(friendIds.map((id) async {
      final b = await client.rpc('get_friend_balance', params: {'user_a': me, 'user_b': id});
      return (b as num?)?.toDouble() ?? 0.0;
    }));
    return balances.fold<double>(0, (a, b) => a + b);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<double>(
      future: _loadTotalBalance(),
      builder: (context, snapshot) {
        final total = snapshot.data ?? 0;
        final loading = friendIds.isNotEmpty && snapshot.connectionState == ConnectionState.waiting;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BalanceHero(balance: total, loading: loading),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GlassButton(
                    label: 'Add expense',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AddExpenseScreen(participantIds: [me, ...friendIds]),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GlassButton(
                    label: 'Settle up',
                    secondary: true,
                    onPressed: () => _showAddMenu(context),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Overall-balance hero: sum of `get_friend_balance` across all accepted
/// friends. Glass-styled (GlassCard + GlassTokens) — no hardcoded colors,
/// no emoji/cat.
class _BalanceHero extends StatelessWidget {
  final double balance;
  final bool loading;
  const _BalanceHero({required this.balance, required this.loading});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final isOwed = balance > 0.005;
    final isOwing = balance < -0.005;
    final color = isOwed ? t.positive : (isOwing ? t.negative : t.settled);
    final label = isOwed ? 'You are owed' : (isOwing ? 'You owe' : 'All settled up');

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: t.textSecondary, fontWeight: FontWeight.w600, fontSize: 15),
          ),
          const SizedBox(height: 8),
          if (loading)
            const SkeletonLoader(height: 32, width: 110)
          else
            Text(
              '₹${balance.abs().toStringAsFixed(2)}',
              style: TextStyle(color: color, fontSize: 32, fontWeight: FontWeight.w800),
            ),
        ],
      ),
    );
  }
}
