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
import 'package:meowes_app/core/theme/app_typography.dart';
import 'package:meowes_app/features/friends/friend_detail_screen.dart';
import 'package:meowes_app/models/app_user.dart';
import 'package:meowes_app/models/friendship.dart';
import 'package:meowes_app/repositories/friend_repository.dart';

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
        final greeting = name != null ? 'Hi, $name' : 'Hi there';

        return GlassScaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              children: [
                _Header(greeting: greeting),
                const SizedBox(height: 20),
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
                      friendRepo: friendRepo,
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

/// Per-friend balance for the Home overview (name + net balance).
class _FriendBal {
  final String id;
  final String name;
  final double balance;
  const _FriendBal({required this.id, required this.name, required this.balance});
}

/// Aggregated overview data: net balance, the owed/owe breakdown, and the
/// non-settled friends sorted by magnitude for the preview list.
class _OverviewData {
  final double net;
  final double owed;
  final double owe;
  final List<_FriendBal> top;
  const _OverviewData({
    required this.net,
    required this.owed,
    required this.owe,
    required this.top,
  });
}

class _OverviewBody extends StatelessWidget {
  final String me;
  final List<String> friendIds;
  final SupabaseClient client;
  final FriendRepository friendRepo;

  const _OverviewBody({
    required this.me,
    required this.friendIds,
    required this.client,
    required this.friendRepo,
  });

  Future<_OverviewData> _load() async {
    if (friendIds.isEmpty) {
      return const _OverviewData(net: 0, owed: 0, owe: 0, top: []);
    }
    final profiles = await friendRepo.getPublicProfiles(friendIds);
    final byId = {for (final p in profiles) p.id: p};
    final entries = await Future.wait(friendIds.map((id) async {
      final b = await client.rpc('get_friend_balance', params: {'user_a': me, 'user_b': id});
      return _FriendBal(
        id: id,
        name: byId[id]?.name ?? '...',
        balance: (b as num?)?.toDouble() ?? 0.0,
      );
    }));
    var net = 0.0, owed = 0.0, owe = 0.0;
    for (final e in entries) {
      net += e.balance;
      if (e.balance > 0.005) {
        owed += e.balance;
      } else if (e.balance < -0.005) {
        owe += -e.balance;
      }
    }
    final top = entries.where((e) => e.balance.abs() > 0.005).toList()
      ..sort((a, b) => b.balance.abs().compareTo(a.balance.abs()));
    return _OverviewData(net: net, owed: owed, owe: owe, top: top);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_OverviewData>(
      future: _load(),
      builder: (context, snapshot) {
        final data = snapshot.data;
        final loading =
            friendIds.isNotEmpty && snapshot.connectionState == ConnectionState.waiting;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _OverallCard(
              balance: data?.net ?? 0,
              loading: loading,
              onAdd: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AddExpenseScreen(participantIds: [me, ...friendIds]),
                ),
              ),
              onSettle: () => _showAddMenu(context),
            ),
            const SizedBox(height: 28),
            _BalancesSection(loading: loading, data: data, friendIds: friendIds),
          ],
        );
      },
    );
  }
}

/// The single "Overall" card: label + big Space Grotesk amount + the two
/// primary actions (Add expense / Settle up) inside the same glass card.
class _OverallCard extends StatelessWidget {
  final double balance;
  final bool loading;
  final VoidCallback onAdd;
  final VoidCallback onSettle;
  const _OverallCard({
    required this.balance,
    required this.loading,
    required this.onAdd,
    required this.onSettle,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final isOwed = balance > 0.005;
    final isOwing = balance < -0.005;
    final color = isOwed ? t.positive : (isOwing ? t.negative : t.settled);
    final label = isOwed
        ? "Overall, you're owed"
        : (isOwing ? 'Overall, you owe' : 'All settled up');

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: t.textSecondary, fontWeight: FontWeight.w500, fontSize: 14),
          ),
          const SizedBox(height: 6),
          if (loading)
            const SkeletonLoader(height: 44, width: 170)
          else
            Text('₹${balance.abs().toStringAsFixed(2)}', style: moneyStyle(color, size: 40)),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: GlassButton(label: 'Add expense', onPressed: onAdd)),
              const SizedBox(width: 12),
              Expanded(
                child: GlassButton(label: 'Settle up', secondary: true, onPressed: onSettle),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Home header: large greeting + a boxed glass notifications button.
class _Header extends StatelessWidget {
  final String greeting;
  const _Header({required this.greeting});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return Row(
      children: [
        Expanded(
          child: Text(
            greeting,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(color: t.textPrimary, fontSize: 26, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const NotificationsScreen()),
          ),
          child: SizedBox(
            width: 46,
            height: 46,
            child: GlassSurface(
              strong: true,
              radius: 14,
              padding: EdgeInsets.zero,
              child: Center(
                child: Icon(Icons.notifications_none, color: t.textPrimary, size: 22),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// "Balances" preview: the top few non-settled friends, tapping into their
/// detail. An empty/settled state fills the space when there's nothing owed.
class _BalancesSection extends StatelessWidget {
  final bool loading;
  final _OverviewData? data;
  final List<String> friendIds;
  const _BalancesSection({required this.loading, required this.data, required this.friendIds});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;

    if (loading) {
      return GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Column(
          children: List.generate(
            3,
            (i) => const Padding(
              padding: EdgeInsets.symmetric(vertical: 13),
              child: Row(
                children: [
                  SkeletonLoader(height: 38, width: 38, radius: 19),
                  SizedBox(width: 12),
                  Expanded(child: SkeletonLoader(height: 14)),
                  SizedBox(width: 12),
                  SkeletonLoader(height: 14, width: 64),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final top = data?.top ?? const <_FriendBal>[];
    if (top.isEmpty) {
      return EmptyStateBox(
        icon: Icons.account_balance_wallet_outlined,
        message: friendIds.isEmpty
            ? 'Add a friend to start splitting expenses.'
            : "You're all settled up.",
      );
    }

    final shown = top.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'BALANCES',
            style: TextStyle(
              color: t.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
            ),
          ),
        ),
        GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            children: [
              for (var i = 0; i < shown.length; i++) ...[
                if (i > 0) Divider(height: 1, color: t.glassBorder),
                _BalanceRow(fb: shown[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _BalanceRow extends StatelessWidget {
  final _FriendBal fb;
  const _BalanceRow({required this.fb});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final owe = fb.balance < 0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => FriendDetailScreen(friendUserId: fb.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              AppAvatar(seed: fb.id, label: fb.name),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fb.name,
                      style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w500, fontSize: 14),
                    ),
                    Text(
                      owe ? 'you owe' : 'owes you',
                      style: TextStyle(color: t.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              BalanceAmount(balance: fb.balance),
            ],
          ),
        ),
      ),
    );
  }
}
