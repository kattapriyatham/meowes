// lib/features/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/theme/app_typography.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/expenses/add_expense_screen.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart'
    show friendRepositoryProvider;
import 'package:meowes_app/features/friends/friend_detail_screen.dart';
import 'package:meowes_app/features/friends/friends_screen.dart';
import 'package:meowes_app/features/activity/activity_screen.dart';
import 'package:meowes_app/features/pet/pet_home_screen.dart';
import 'package:meowes_app/features/profile/profile_screen.dart';
import 'package:meowes_app/models/app_user.dart';
import 'package:meowes_app/models/friendship.dart';
import 'package:meowes_app/models/pet.dart';
import 'package:meowes_app/repositories/friend_repository.dart';
import 'package:meowes_app/repositories/pet_repository.dart';

/// Home tab — warm "paper" dashboard: greeting header, an overall-balance
/// card (with the Meowes cat + primary actions), and a Balances preview.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    final friendRepo = ref.watch(friendRepositoryProvider);
    final me = client.auth.currentUser!.id;
    ref.watch(dataChangedTickerProvider);

    return FutureBuilder<AppUser?>(
      future: friendRepo.getMyProfile(),
      builder: (context, profileSnapshot) {
        final name = profileSnapshot.data?.name;
        final greeting = name != null ? 'Hi, $name' : 'Hi there';

        return GlassScaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
              children: [
                _Header(greeting: greeting),
                const SizedBox(height: 22),
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

// ── Header ──────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String greeting;
  const _Header({required this.greeting});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: t.textPrimary,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SoftIconButton(
          icon: Icons.notifications_none,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ActivityScreen()),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ProfileScreen()),
          ),
          child: _ProfileAvatarPlaceholder(),
        ),
      ],
    );
  }
}

/// Placeholder for the user's profile photo (drop assets/images/profile.png).
class _ProfileAvatarPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return ClipOval(
      child: Image.asset(
        'assets/images/profile.png',
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => Container(
          width: 48,
          height: 48,
          color: t.textPrimary.withValues(alpha: 0.06),
          alignment: Alignment.center,
          child: Icon(Icons.person, color: t.textSecondary, size: 24),
        ),
      ),
    );
  }
}

// ── Overview body ───────────────────────────────────────────────────────

class _FriendBal {
  final String id;
  final String name;
  final double balance;
  const _FriendBal({
    required this.id,
    required this.name,
    required this.balance,
  });
}

class _OverviewData {
  final double net;
  final List<_FriendBal> top;
  const _OverviewData({required this.net, required this.top});
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
    if (friendIds.isEmpty) return const _OverviewData(net: 0, top: []);
    final profiles = await friendRepo.getPublicProfiles(friendIds);
    final byId = {for (final p in profiles) p.id: p};
    final entries = await Future.wait(
      friendIds.map((id) async {
        final b = await client.rpc(
          'get_friend_balance',
          params: {'user_a': me, 'user_b': id},
        );
        return _FriendBal(
          id: id,
          name: byId[id]?.name ?? '...',
          balance: (b as num?)?.toDouble() ?? 0.0,
        );
      }),
    );
    final net = entries.fold<double>(0, (a, e) => a + e.balance);
    final top = entries.where((e) => e.balance.abs() > 0.005).toList()
      ..sort((a, b) => b.balance.abs().compareTo(a.balance.abs()));
    return _OverviewData(net: net, top: top);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return FutureBuilder<_OverviewData>(
      future: _load(),
      builder: (context, snapshot) {
        final data = snapshot.data;
        final loading =
            friendIds.isNotEmpty &&
            snapshot.connectionState == ConnectionState.waiting;

        // Stack (rather than nesting the cat inside just the balance card)
        // so the cat paints on top of everything below it too — its lower
        // half overlaps the Balances card, reading as the cat sitting on
        // top of it instead of being hidden behind it.
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _BalanceCard(
                  balance: data?.net ?? 0,
                  loading: loading,
                  onAdd: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          AddExpenseScreen(participantIds: [me, ...friendIds]),
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                // "View all" used to live here, top-right of this header —
                // but that's exactly where the cat now overlaps (it paints
                // on top, per the Stack above), so it was getting hidden
                // behind it. Moved to a footer row inside the balances
                // card instead, well clear of the cat.
                Text(
                  'Balances',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _BalancesCard(
                  loading: loading,
                  data: data,
                  friendIds: friendIds,
                ),
              ],
            ),
            const Positioned(
              top: 10,
              right: -6,
              child: _PetCatWidget(width: 200),
            ),
          ],
        );
      },
    );
  }
}

// ── Balance card (with cat + actions) ─────────────────────────────────────

class _BalanceCard extends StatelessWidget {
  final double balance;
  final bool loading;
  final VoidCallback onAdd;
  const _BalanceCard({
    required this.balance,
    required this.loading,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final isOwed = balance > 0.005;
    final isOwing = balance < -0.005;
    final label = isOwed
        ? 'You are owed'
        : (isOwing ? 'You owe' : 'All settled up');
    return SoftCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Keep the numeric column clear of the cat on the right.
          Padding(
            padding: const EdgeInsets.only(right: 116),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: t.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 8),
                if (loading)
                  const SkeletonLoader(height: 40, width: 150)
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        child: Text(
                          '₹${balance.abs().toStringAsFixed(2)}',
                          style: moneyStyle(t.textPrimary, size: 34),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (isOwed)
                        Icon(Icons.north_east, size: 18, color: t.positive)
                      else if (isOwing)
                        Icon(Icons.south_east, size: 18, color: t.negative),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: PillButton(
                label: 'Add expense',
                primary: true,
                onTap: onAdd,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pet cat, mood-aware teaser — tap to open the dedicated Pet screen ──────
class _PetCatWidget extends ConsumerStatefulWidget {
  final double width;
  const _PetCatWidget({required this.width});

  @override
  ConsumerState<_PetCatWidget> createState() => _PetCatWidgetState();
}

class _PetCatWidgetState extends ConsumerState<_PetCatWidget> {
  Pet? _pet;

  @override
  void initState() {
    super.initState();
    _loadAndCheckIn();
  }

  Future<void> _loadAndCheckIn() async {
    final repo = ref.read(petRepositoryProvider);
    final pet = await repo.getOrCreatePet();
    if (!mounted) return;
    setState(() => _pet = pet);

    try {
      final afterCheckIn = await repo.dailyCheckIn();
      if (!mounted) return;
      setState(() => _pet = afterCheckIn);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(content: Text('Daily check-in: +5 coins')),
          );
      }
    } on AlreadyCheckedInException {
      // Already checked in today — silent no-op.
    }
  }

  IconData _moodIcon(MoodState mood) {
    switch (mood) {
      case MoodState.sad:
        return Icons.sentiment_very_dissatisfied;
      case MoodState.content:
        return Icons.sentiment_neutral;
      case MoodState.happy:
        return Icons.sentiment_satisfied;
      case MoodState.ecstatic:
        return Icons.sentiment_very_satisfied;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final pet = _pet;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const PetHomeScreen())),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (pet != null)
            Padding(
              // The cat image below is deliberately bled off the right
              // edge (Positioned right: -6 in the parent), but this row
              // shouldn't be — without its own margin it rides that same
              // edge and gets clipped.
              padding: const EdgeInsets.only(right: 25),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_moodIcon(pet.mood), size: 16, color: t.textSecondary),
                  const SizedBox(width: 4),
                  Icon(Icons.pets, size: 14, color: t.textMuted),
                  const SizedBox(width: 2),
                  Text(
                    '${pet.coins}',
                    style: TextStyle(color: t.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
          Image.asset(
            'assets/images/pet/cat_idle.png',
            width: widget.width,
            fit: BoxFit.fitWidth,
            errorBuilder: (context, error, stack) => Container(
              width: widget.width,
              height: widget.width * 0.7,
              decoration: BoxDecoration(
                color: t.textPrimary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(26),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.pets,
                    size: widget.width * 0.22,
                    color: t.textSecondary,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'cat',
                    style: TextStyle(color: t.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Balances preview ──────────────────────────────────────────────────────

class _BalancesCard extends StatelessWidget {
  final bool loading;
  final _OverviewData? data;
  final List<String> friendIds;
  const _BalancesCard({
    required this.loading,
    required this.data,
    required this.friendIds,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;

    if (loading) {
      return SoftCard(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        child: Column(
          children: List.generate(
            3,
            (i) => const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  SkeletonLoader(height: 44, width: 44, radius: 22),
                  SizedBox(width: 14),
                  Expanded(child: SkeletonLoader(height: 14)),
                  SizedBox(width: 14),
                  SkeletonLoader(height: 14, width: 70),
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
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: t.textPrimary.withValues(alpha: 0.06)),
            _BalanceRow(fb: shown[i]),
          ],
          Divider(height: 1, color: t.textPrimary.withValues(alpha: 0.06)),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const FriendsScreen())),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'View all',
                      style: TextStyle(color: t.textMuted, fontSize: 13),
                    ),
                    const SizedBox(width: 3),
                    Icon(Icons.arrow_forward, size: 15, color: t.textMuted),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
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
          MaterialPageRoute(
            builder: (_) => FriendDetailScreen(friendUserId: fb.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              _MonoAvatar(label: fb.name),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fb.name,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      owe ? 'you owe' : 'owes you',
                      style: TextStyle(color: t.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Text(
                '${owe ? '-' : '+'}₹${fb.balance.abs().toStringAsFixed(2)}',
                style: moneyStyle(owe ? t.negative : t.positive, size: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Monochrome tan avatar (initial on a soft warm circle) for the paper theme.
class _MonoAvatar extends StatelessWidget {
  final String label;
  const _MonoAvatar({required this.label});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: t.textPrimary.withValues(alpha: 0.06),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        label.isNotEmpty ? label[0].toUpperCase() : '?',
        style: TextStyle(
          color: t.textSecondary,
          fontWeight: FontWeight.w700,
          fontSize: 17,
        ),
      ),
    );
  }
}
