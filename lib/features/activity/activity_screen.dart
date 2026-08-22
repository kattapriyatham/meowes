// lib/features/activity/activity_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/expenses/expense_detail_screen.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart' show friendRepositoryProvider;
import 'package:meowes_app/features/settlements/settle_up_screen.dart' show settlementRepositoryProvider;
import 'package:meowes_app/models/activity_item.dart';
import 'package:meowes_app/models/app_user.dart';
import 'package:meowes_app/models/friendship.dart';
import 'package:meowes_app/models/pet.dart';
import 'package:meowes_app/models/settlement.dart';
import 'package:meowes_app/repositories/activity_repository.dart';
import 'package:meowes_app/repositories/expense_repository.dart';
import 'package:meowes_app/repositories/friend_repository.dart';
import 'package:meowes_app/repositories/pet_repository.dart';
import 'package:meowes_app/repositories/settlement_repository.dart';

/// Today's pet-care events (currently just the daily check-in) derived
/// straight from the `pets` row, the same way friend requests/settlements
/// below are derived from their own tables — no separate notifications log
/// to keep in sync.
final todaysPetEventsProvider = FutureProvider.autoDispose<Pet>(
  (ref) => ref.watch(petRepositoryProvider).getOrCreatePet(),
);

/// Activity tab: everything about the signed-in user in one place —
/// pending things that need a response (friend requests, settlements to
/// confirm, today's check-in) pinned at the top, and a chronological
/// history feed of expenses/settlements/pet activity below. Replaces the
/// former separate NotificationsScreen, which covered only the "pending"
/// half of this and duplicated the same two queries.
class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    final friendRepo = ref.watch(friendRepositoryProvider);
    final settlementRepo = ref.watch(settlementRepositoryProvider);
    final activityRepo = ref.watch(activityRepositoryProvider);
    final me = client.auth.currentUser!.id;
    final petAsync = ref.watch(todaysPetEventsProvider);
    final checkedInToday = petAsync.asData?.value.lastCheckinAt != null &&
        DateUtils.isSameDay(petAsync.asData!.value.lastCheckinAt, DateTime.now());

    return GlassScaffold(
      appBar: const GlassAppBar(title: 'Activity'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          children: [
            StreamBuilder<List<Friendship>>(
              stream: friendRepo.watchFriendships(),
              builder: (context, friendshipSnapshot) {
                final pendingRequesterIds = (friendshipSnapshot.data ?? [])
                    .where((f) => f.status == FriendshipStatus.pending && f.requestedBy != me)
                    .map((f) => f.userIdA == me ? f.userIdB : f.userIdA)
                    .toList();

                return StreamBuilder<List<Settlement>>(
                  stream: settlementRepo.watchPendingForMe(),
                  builder: (context, settlementSnapshot) {
                    if (friendshipSnapshot.hasError || settlementSnapshot.hasError) {
                      final t = Theme.of(context).extension<GlassTokens>()!;
                      return Text(
                        'Something went wrong loading activity.',
                        style: TextStyle(color: t.negative),
                      );
                    }

                    final pendingLoading = !friendshipSnapshot.hasData || !settlementSnapshot.hasData;
                    final settlements = settlementSnapshot.data ?? [];

                    return FutureBuilder<List<ActivityItem>>(
                      future: activityRepo.getMyActivityFeed(),
                      builder: (context, feedSnapshot) {
                        final feedLoading = feedSnapshot.connectionState == ConnectionState.waiting;
                        final feed = feedSnapshot.data ?? [];

                        if (pendingLoading || feedLoading) {
                          return const _ActivitySkeleton();
                        }

                        final nothingPending =
                            pendingRequesterIds.isEmpty && settlements.isEmpty && !checkedInToday;
                        if (nothingPending && feed.isEmpty) {
                          return const EmptyStateBox(
                            icon: Icons.show_chart,
                            message: 'No activity yet.',
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (checkedInToday) ...[
                              const _SectionLabel(title: 'Today'),
                              const SizedBox(height: 12),
                              const _DailyCheckInCard(),
                              const SizedBox(height: 24),
                            ],
                            if (pendingRequesterIds.isNotEmpty) ...[
                              const _SectionLabel(title: 'Friend requests'),
                              const SizedBox(height: 12),
                              _PendingRequestsCard(friendRepo: friendRepo, requesterIds: pendingRequesterIds),
                              const SizedBox(height: 24),
                            ],
                            if (settlements.isNotEmpty) ...[
                              const _SectionLabel(title: 'Settlements to confirm'),
                              const SizedBox(height: 12),
                              _PendingSettlementsCard(
                                friendRepo: friendRepo,
                                settlementRepo: settlementRepo,
                                settlements: settlements,
                                ref: ref,
                              ),
                              const SizedBox(height: 24),
                            ],
                            if (feed.isNotEmpty) ...[
                              const _SectionLabel(title: 'History'),
                              const SizedBox(height: 12),
                              _HistoryCard(friendRepo: friendRepo, items: feed, ref: ref),
                            ],
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String title;
  const _SectionLabel({required this.title});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return Text(
      title,
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: t.textPrimary),
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

class _ActivitySkeleton extends StatelessWidget {
  const _ActivitySkeleton();

  @override
  Widget build(BuildContext context) {
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
                SkeletonLoader(height: 14, width: 140),
                SizedBox(height: 6),
                SkeletonLoader(height: 10, width: 90),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyCheckInCard extends StatelessWidget {
  const _DailyCheckInCard();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return SoftCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: t.positiveTint, shape: BoxShape.circle),
            child: Icon(Icons.event_available, color: t.positive, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "You checked in today — +5 coins for your cat",
              style: TextStyle(fontWeight: FontWeight.w600, color: t.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingRequestsCard extends StatelessWidget {
  final FriendRepository friendRepo;
  final List<String> requesterIds;
  const _PendingRequestsCard({required this.friendRepo, required this.requesterIds});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AppUser>>(
      future: friendRepo.getPublicProfiles(requesterIds),
      builder: (context, snapshot) {
        final names = {for (final p in snapshot.data ?? <AppUser>[]) p.id: p.name};
        return GlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < requesterIds.length; i++) ...[
                if (i > 0) const _RowDivider(),
                _PendingRequestRow(
                  requesterId: requesterIds[i],
                  name: names[requesterIds[i]] ?? '...',
                  friendRepo: friendRepo,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PendingRequestRow extends StatelessWidget {
  final String requesterId;
  final String name;
  final FriendRepository friendRepo;
  const _PendingRequestRow({required this.requesterId, required this.name, required this.friendRepo});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          AppAvatar(seed: requesterId, label: name),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: t.textPrimary),
            ),
          ),
          IconButton(
            tooltip: 'Decline',
            icon: Icon(Icons.close, color: t.negative),
            onPressed: () => friendRepo.declineFriendRequest(requesterId),
          ),
          IconButton(
            tooltip: 'Accept',
            icon: Icon(Icons.check_circle, color: t.positive),
            onPressed: () => friendRepo.acceptFriendRequest(requesterId),
          ),
        ],
      ),
    );
  }
}

class _PendingSettlementsCard extends StatelessWidget {
  final FriendRepository friendRepo;
  final SettlementRepository settlementRepo;
  final List<Settlement> settlements;
  final WidgetRef ref;
  const _PendingSettlementsCard({
    required this.friendRepo,
    required this.settlementRepo,
    required this.settlements,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final fromUserIds = settlements.map((s) => s.fromUser).toSet().toList();
    return FutureBuilder<List<AppUser>>(
      future: friendRepo.getPublicProfiles(fromUserIds),
      builder: (context, snapshot) {
        final names = {for (final p in snapshot.data ?? <AppUser>[]) p.id: p.name};
        return GlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < settlements.length; i++) ...[
                if (i > 0) const _RowDivider(),
                _PendingSettlementRow(
                  settlement: settlements[i],
                  name: names[settlements[i].fromUser] ?? '...',
                  settlementRepo: settlementRepo,
                  ref: ref,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PendingSettlementRow extends StatelessWidget {
  final Settlement settlement;
  final String name;
  final SettlementRepository settlementRepo;
  final WidgetRef ref;
  const _PendingSettlementRow({
    required this.settlement,
    required this.name,
    required this.settlementRepo,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          AppAvatar(seed: settlement.fromUser, label: name),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$name paid you',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: t.textPrimary),
            ),
          ),
          Text(
            '+₹${(settlement.amountMinorUnits / 100).toStringAsFixed(2)}',
            style: TextStyle(fontWeight: FontWeight.w700, color: t.positive),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Confirm',
            icon: Icon(Icons.check_circle, color: t.positive),
            onPressed: () async {
              await settlementRepo.confirmSettlement(settlement.id);
              notifyDataChanged(ref);
            },
          ),
        ],
      ),
    );
  }
}

/// Chronological history: expenses, confirmed settlements, and pet-coin
/// spending, in one list ordered newest-first (see get_my_activity_feed()).
class _HistoryCard extends StatelessWidget {
  final FriendRepository friendRepo;
  final List<ActivityItem> items;
  final WidgetRef ref;
  const _HistoryCard({required this.friendRepo, required this.items, required this.ref});

  @override
  Widget build(BuildContext context) {
    final counterpartIds = items.map((i) => i.counterpartId).whereType<String>().toSet().toList();
    return FutureBuilder<List<AppUser>>(
      future: friendRepo.getPublicProfiles(counterpartIds),
      builder: (context, snapshot) {
        final names = {for (final p in snapshot.data ?? <AppUser>[]) p.id: p.name};
        return GlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const _RowDivider(),
                _HistoryRow(item: items[i], counterpartName: names[items[i].counterpartId], ref: ref),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final ActivityItem item;
  final String? counterpartName;
  final WidgetRef ref;
  const _HistoryRow({required this.item, required this.counterpartName, required this.ref});

  IconData get _icon {
    switch (item.kind) {
      case ActivityKind.expense:
        return Icons.receipt_long_outlined;
      case ActivityKind.settlement:
        return Icons.swap_horiz;
      case ActivityKind.petActivity:
        return Icons.pets;
    }
  }

  String get _title {
    final name = counterpartName ?? '...';
    switch (item.kind) {
      case ActivityKind.expense:
        return item.title ?? 'Expense';
      case ActivityKind.settlement:
        return item.isMine == true ? 'You paid $name' : '$name paid you';
      case ActivityKind.petActivity:
        return item.title ?? 'Pet activity';
    }
  }

  String get _subtitle {
    final name = counterpartName ?? '...';
    switch (item.kind) {
      case ActivityKind.expense:
        return item.isMine == true ? 'You paid' : 'Paid by $name';
      case ActivityKind.settlement:
        return 'Settled up';
      case ActivityKind.petActivity:
        return 'Spent on your cat';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;

    return InkWell(
      onTap: item.kind == ActivityKind.expense
          ? () async {
              final expense = await ref.read(expenseRepositoryProvider).getExpenseById(item.refId);
              if (context.mounted) {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ExpenseDetailScreen(expense: expense)),
                );
              }
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: t.glassBorder, shape: BoxShape.circle),
              child: Icon(_icon, size: 18, color: t.textSecondary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: t.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitle,
                    style: TextStyle(fontSize: 12, color: t.textMuted),
                  ),
                ],
              ),
            ),
            item.kind == ActivityKind.petActivity
                ? CoinAmount(amount: -item.amount.round())
                : Text(
                    '₹${item.amount.toStringAsFixed(2)}',
                    style: TextStyle(fontWeight: FontWeight.w700, color: t.textPrimary),
                  ),
          ],
        ),
      ),
    );
  }
}
