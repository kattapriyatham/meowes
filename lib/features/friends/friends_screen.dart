// lib/features/friends/friends_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/core/app_theme.dart';
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
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  String _query = '';
  FriendRepository? _streamRepository;
  Stream<List<Friendship>>? _friendshipStream;

  Stream<List<Friendship>> _watchFriendships(FriendRepository repository) {
    if (!identical(_streamRepository, repository)) {
      _streamRepository = repository;
      _friendshipStream = repository.watchFriendships();
    }
    return _friendshipStream!;
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(supabaseClientProvider);
    final friendRepo = ref.watch(friendRepositoryProvider);
    final me = client.auth.currentUser!.id;
    final dataVersion = ref.watch(dataChangedTickerProvider);
    final t = Theme.of(context).extension<GlassTokens>()!;
    final friendshipStream = _watchFriendships(friendRepo);

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/friends-hero.png',
                key: const Key('friends-hero-image'),
                fit: BoxFit.cover,
                alignment: Alignment.bottomCenter,
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.22),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.08),
                    ],
                    stops: const [0, 0.42, 1],
                  ),
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 18, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Friends',
                            style: TextStyle(
                              color: AppColors.textDark,
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Split bills, make memories',
                            style: TextStyle(
                              color: AppColors.textDark,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Material(
                      color: Colors.white.withValues(alpha: 0.92),
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: 'Add friend',
                        icon: Icon(
                          Icons.person_add_alt_1_rounded,
                          color: t.textPrimary,
                        ),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AddFriendScreen(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            DraggableScrollableSheet(
              initialChildSize: 0.52,
              minChildSize: 0.52,
              maxChildSize: 1,
              snap: true,
              snapSizes: const [0.52, 1],
              builder: (context, scrollController) => Container(
                key: const Key('friends-scroll-sheet'),
                decoration: BoxDecoration(
                  color: t.cardColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(30),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: t.cardShadow,
                      blurRadius: 26,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: true,
                  bottom: false,
                  child: CustomScrollView(
                    controller: scrollController,
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Center(
                                child: Container(
                                  width: 44,
                                  height: 4,
                                  margin: const EdgeInsets.only(bottom: 18),
                                  decoration: BoxDecoration(
                                    color: t.textMuted.withValues(alpha: 0.45),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                ),
                              ),
                              TextField(
                                key: const Key('friends-search-field'),
                                onChanged: (value) =>
                                    setState(() => _query = value.trim()),
                                textInputAction: TextInputAction.search,
                                decoration: const InputDecoration(
                                  hintText: 'Search friends',
                                  prefixIcon: Icon(Icons.search_rounded),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 132),
                        sliver: SliverToBoxAdapter(
                          child: StreamBuilder<List<Friendship>>(
                            stream: friendshipStream,
                            builder: (context, snapshot) {
                              final friendIds = (snapshot.data ?? [])
                                  .where(
                                    (f) =>
                                        f.status == FriendshipStatus.accepted,
                                  )
                                  .map(
                                    (f) =>
                                        f.userIdA == me ? f.userIdB : f.userIdA,
                                  )
                                  .toList();
                              return _FriendsList(
                                me: me,
                                friendIds: friendIds,
                                query: _query,
                                dataVersion: dataVersion,
                                client: client,
                                friendRepo: friendRepo,
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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

class _FriendsList extends StatefulWidget {
  final String me;
  final List<String> friendIds;
  final String query;
  final int dataVersion;
  final SupabaseClient client;
  final FriendRepository friendRepo;

  const _FriendsList({
    required this.me,
    required this.friendIds,
    required this.query,
    required this.dataVersion,
    required this.client,
    required this.friendRepo,
  });

  @override
  State<_FriendsList> createState() => _FriendsListState();
}

class _FriendsListState extends State<_FriendsList> {
  late Future<_FriendsData> _future;
  late String _friendIdsKey;

  @override
  void initState() {
    super.initState();
    _friendIdsKey = _idsKey(widget.friendIds);
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _FriendsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextKey = _idsKey(widget.friendIds);
    if (nextKey != _friendIdsKey ||
        !identical(oldWidget.client, widget.client) ||
        !identical(oldWidget.friendRepo, widget.friendRepo) ||
        oldWidget.me != widget.me ||
        oldWidget.dataVersion != widget.dataVersion) {
      _friendIdsKey = nextKey;
      _future = _load();
    }
  }

  String _idsKey(List<String> ids) => ids.join('\u0000');

  Future<_FriendsData> _load() async {
    if (widget.friendIds.isEmpty) {
      return const _FriendsData(profiles: {}, balances: {});
    }
    final profiles = await widget.friendRepo.getPublicProfiles(
      widget.friendIds,
    );
    final balanceEntries = await Future.wait(
      widget.friendIds.map((id) async {
        final b = await widget.client.rpc(
          'get_friend_balance',
          params: {'user_a': widget.me, 'user_b': id},
        );
        return MapEntry(id, (b as num?)?.toDouble() ?? 0.0);
      }),
    );
    return _FriendsData(
      profiles: {for (final p in profiles) p.id: p},
      balances: Map.fromEntries(balanceEntries),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_FriendsData>(
      future: _future,
      builder: (context, snapshot) {
        final loading =
            widget.friendIds.isNotEmpty &&
            snapshot.connectionState == ConnectionState.waiting;

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

        if (widget.friendIds.isEmpty) {
          return const EmptyStateBox(
            icon: Icons.people_outline,
            message: 'No friends yet. Add one to start splitting expenses.',
          );
        }

        final data =
            snapshot.data ?? const _FriendsData(profiles: {}, balances: {});
        final visibleFriendIds = widget.friendIds.where((id) {
          final name = data.profiles[id]?.name ?? '';
          return widget.query.isEmpty ||
              name.toLowerCase().contains(widget.query.toLowerCase());
        }).toList();

        if (visibleFriendIds.isEmpty) {
          return EmptyStateBox(
            icon: Icons.search_off_rounded,
            message: 'No friends match "${widget.query}".',
          );
        }

        return GlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < visibleFriendIds.length; i++) ...[
                if (i > 0) const _RowDivider(),
                _FriendRow(
                  friendUserId: visibleFriendIds[i],
                  name: data.profiles[visibleFriendIds[i]]?.name ?? '...',
                  balance: data.balances[visibleFriendIds[i]] ?? 0,
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
    return Divider(
      height: 1,
      thickness: 1,
      color: t.glassBorder,
      indent: 16,
      endIndent: 16,
    );
  }
}

class _FriendRow extends StatelessWidget {
  final String friendUserId;
  final String name;
  final double balance;
  const _FriendRow({
    required this.friendUserId,
    required this.name,
    required this.balance,
  });

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
          MaterialPageRoute(
            builder: (_) => FriendDetailScreen(friendUserId: friendUserId),
          ),
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
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: t.textPrimary,
                      ),
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
