// lib/features/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart';
import 'package:meowes_app/features/friends/friend_detail_screen.dart';
import 'package:meowes_app/features/groups/create_group_screen.dart';
import 'package:meowes_app/features/groups/group_detail_screen.dart';
import 'package:meowes_app/models/app_user.dart';
import 'package:meowes_app/models/friendship.dart';
import 'package:meowes_app/models/group.dart';
import 'package:meowes_app/repositories/friend_repository.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    final friendRepo = ref.watch(friendRepositoryProvider);
    final groupRepo = ref.watch(groupRepositoryProvider);
    final me = client.auth.currentUser!.id;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          children: [
            _GreetingHeader(friendRepo: friendRepo),
            const SizedBox(height: 20),
            StreamBuilder<List<Friendship>>(
              stream: friendRepo.watchFriendships(),
              builder: (context, snapshot) {
                final friendIds = (snapshot.data ?? [])
                    .where((f) => f.status == FriendshipStatus.accepted)
                    .map((f) => f.userIdA == me ? f.userIdB : f.userIdA)
                    .toList();
                return _FriendsAndSummary(
                  me: me,
                  friendIds: friendIds,
                  client: client,
                  friendRepo: friendRepo,
                );
              },
            ),
            const SizedBox(height: 28),
            const SectionHeader(title: 'Groups'),
            const SizedBox(height: 12),
            StreamBuilder<List<Group>>(
              stream: groupRepo.watchMyGroups(),
              builder: (context, snapshot) {
                final groups = snapshot.data ?? [];
                if (groups.isEmpty) {
                  return const EmptyStateBox(
                    icon: Icons.groups_2_outlined,
                    message: 'No groups yet — create one to split with a crew.',
                  );
                }
                return Column(
                  children: [
                    for (final g in groups) ...[
                      _GroupTile(group: g, me: me, client: client),
                      const SizedBox(height: 10),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddMenu(context),
        child: const Icon(Icons.add),
      ),
    );
  }

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
}

class _GreetingHeader extends StatelessWidget {
  final FriendRepository friendRepo;
  const _GreetingHeader({required this.friendRepo});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppUser?>(
      future: friendRepo.getMyProfile(),
      builder: (context, snapshot) {
        final name = snapshot.data?.name;
        return Row(
          children: [
            Expanded(
              child: Text(
                name != null ? 'Hi $name! 👋' : 'Hi there! 👋',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: const Icon(Icons.notifications_none, color: AppColors.textDark),
            ),
          ],
        );
      },
    );
  }
}

class _FriendsData {
  final Map<String, AppUser> profiles;
  final Map<String, double> balances;
  const _FriendsData({required this.profiles, required this.balances});
}

class _FriendsAndSummary extends StatelessWidget {
  final String me;
  final List<String> friendIds;
  final SupabaseClient client;
  final FriendRepository friendRepo;

  const _FriendsAndSummary({
    required this.me,
    required this.friendIds,
    required this.client,
    required this.friendRepo,
  });

  Future<_FriendsData> _load() async {
    if (friendIds.isEmpty) {
      return const _FriendsData(profiles: {}, balances: {});
    }
    final profiles = await friendRepo.getPublicProfiles(friendIds);
    final balanceEntries = await Future.wait(friendIds.map((id) async {
      final b = await client.rpc('get_friend_balance', params: {'user_a': me, 'user_b': id});
      return MapEntry(id, (b as num?)?.toDouble() ?? 0.0);
    }));
    return _FriendsData(
      profiles: {for (final p in profiles) p.id: p},
      balances: Map.fromEntries(balanceEntries),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_FriendsData>(
      future: _load(),
      builder: (context, snapshot) {
        final data = snapshot.data ?? const _FriendsData(profiles: {}, balances: {});
        final total = data.balances.values.fold<double>(0, (a, b) => a + b);
        final loading = friendIds.isNotEmpty && snapshot.connectionState == ConnectionState.waiting;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BalanceSummaryCard(balance: total, loading: loading),
            const SizedBox(height: 24),
            const SectionHeader(title: 'Friends'),
            const SizedBox(height: 12),
            if (friendIds.isEmpty)
              const EmptyStateBox(
                icon: Icons.pets,
                message: 'No friends yet — add one to start splitting expenses.',
              )
            else
              Column(
                children: [
                  for (final id in friendIds) ...[
                    _FriendTile(
                      friendUserId: id,
                      name: data.profiles[id]?.name ?? '...',
                      balance: data.balances[id] ?? 0,
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
          ],
        );
      },
    );
  }
}

class _FriendTile extends StatelessWidget {
  final String friendUserId;
  final String name;
  final double balance;
  const _FriendTile({required this.friendUserId, required this.name, required this.balance});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => FriendDetailScreen(friendUserId: friendUserId)),
      ),
      child: Row(
        children: [
          AppAvatar(seed: friendUserId, label: name),
          const SizedBox(width: 12),
          Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
          BalanceAmount(balance: balance),
        ],
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  final Group group;
  final String me;
  final SupabaseClient client;
  const _GroupTile({required this.group, required this.me, required this.client});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: client.rpc('get_group_debts', params: {'target_group_id': group.id}),
      builder: (context, snapshot) {
        final debts = (snapshot.data as List<dynamic>?) ?? [];
        var net = 0.0;
        for (final d in debts) {
          final amount = double.tryParse(d['amount'].toString()) ?? 0;
          if (d['to_user'] == me) net += amount;
          if (d['from_user'] == me) net -= amount;
        }
        return AppCard(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => GroupDetailScreen(groupId: group.id)),
          ),
          child: Row(
            children: [
              AppAvatar(seed: group.id, icon: Icons.groups),
              const SizedBox(width: 12),
              Expanded(child: Text(group.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
              BalanceAmount(balance: net),
            ],
          ),
        );
      },
    );
  }
}
