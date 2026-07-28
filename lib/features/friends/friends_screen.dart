// lib/features/friends/friends_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart';
import 'package:meowes_app/features/friends/friend_detail_screen.dart';
import 'package:meowes_app/models/app_user.dart';
import 'package:meowes_app/models/friendship.dart';
import 'package:meowes_app/repositories/friend_repository.dart';

/// Friends tab: accepted friends with their per-friend balance. The
/// friendship stream + accepted-id filter and the profile/balance loading
/// are lifted verbatim from `home_screen.dart`'s `_FriendsAndSummary` so
/// results are identical to the Home tab's friends section; only the
/// presentation here is glass.
class FriendsScreen extends ConsumerWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    final friendRepo = ref.watch(friendRepositoryProvider);
    final me = client.auth.currentUser!.id;

    return GlassScaffold(
      appBar: GlassAppBar(
        title: 'Friends',
        actions: [
          IconButton(
            tooltip: 'Add friend',
            icon: const Icon(Icons.person_add_alt),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AddFriendScreen()),
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
                return _FriendsList(
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
  }
}

class _FriendsData {
  final Map<String, AppUser> profiles;
  final Map<String, double> balances;
  const _FriendsData({required this.profiles, required this.balances});
}

class _FriendsList extends StatelessWidget {
  final String me;
  final List<String> friendIds;
  final SupabaseClient client;
  final FriendRepository friendRepo;

  const _FriendsList({
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
        final loading = friendIds.isNotEmpty && snapshot.connectionState == ConnectionState.waiting;

        if (snapshot.hasError) {
          final t = Theme.of(context).extension<GlassTokens>()!;
          return Text(
            'Something went wrong loading friends.',
            style: TextStyle(color: t.negative),
          );
        }

        if (loading) {
          return GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const _RowDivider(),
                  const _SkeletonRow(),
                ],
              ],
            ),
          );
        }

        if (friendIds.isEmpty) {
          return const EmptyStateBox(
            icon: Icons.people_outline,
            message: 'No friends yet. Add one to start splitting expenses.',
          );
        }

        final data = snapshot.data ?? const _FriendsData(profiles: {}, balances: {});
        return GlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < friendIds.length; i++) ...[
                if (i > 0) const _RowDivider(),
                _FriendRow(
                  friendUserId: friendIds[i],
                  name: data.profiles[friendIds[i]]?.name ?? '...',
                  balance: data.balances[friendIds[i]] ?? 0,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return Divider(height: 1, thickness: 1, color: t.glassBorder, indent: 16, endIndent: 16);
  }
}

class _FriendRow extends StatelessWidget {
  final String friendUserId;
  final String name;
  final double balance;
  const _FriendRow({required this.friendUserId, required this.name, required this.balance});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final subline = balance > 0.005
        ? 'owes you'
        : (balance < -0.005 ? 'you owe' : 'settled up');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => FriendDetailScreen(friendUserId: friendUserId)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              AppAvatar(seed: friendUserId, label: name),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: t.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subline,
                      style: TextStyle(fontSize: 12, color: t.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              BalanceAmount(balance: balance),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const SkeletonLoader(height: 44, width: 44, radius: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonLoader(height: 14, width: 120),
                SizedBox(height: 6),
                SkeletonLoader(height: 10, width: 70),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const SkeletonLoader(height: 14, width: 50),
        ],
      ),
    );
  }
}
