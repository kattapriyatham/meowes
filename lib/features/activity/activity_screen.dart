// lib/features/activity/activity_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart' show friendRepositoryProvider;
import 'package:meowes_app/features/settlements/settle_up_screen.dart' show settlementRepositoryProvider;
import 'package:meowes_app/models/app_user.dart';
import 'package:meowes_app/models/friendship.dart';
import 'package:meowes_app/models/settlement.dart';
import 'package:meowes_app/repositories/friend_repository.dart';
import 'package:meowes_app/repositories/settlement_repository.dart';

/// Activity tab: things that need the signed-in user's attention.
///
/// There is no dedicated global activity/feed repository method today — the
/// only existing "activity" query, `ExpenseRepository.getFriendActivity`, is
/// scoped to a single friend and can't be used for an app-wide feed without
/// a new backend query (out of scope for this task; see task-14-report.md).
/// So this screen deliberately mirrors `NotificationsScreen`'s data source:
/// pending friend requests from `FriendRepository.watchFriendships()`
/// (filtered to requests addressed to me) and pending settlements from
/// `SettlementRepository.watchPendingForMe()`, restyled in glass and grouped
/// under section labels.
class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    final friendRepo = ref.watch(friendRepositoryProvider);
    final settlementRepo = ref.watch(settlementRepositoryProvider);
    final me = client.auth.currentUser!.id;

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

                    final loading = !friendshipSnapshot.hasData || !settlementSnapshot.hasData;
                    if (loading) {
                      return const _ActivitySkeleton();
                    }

                    final settlements = settlementSnapshot.data ?? [];
                    if (pendingRequesterIds.isEmpty && settlements.isEmpty) {
                      return const EmptyStateBox(
                        icon: Icons.show_chart,
                        message: 'No activity yet.',
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                          ),
                        ],
                      ],
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
  const _PendingSettlementsCard({
    required this.friendRepo,
    required this.settlementRepo,
    required this.settlements,
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
  const _PendingSettlementRow({required this.settlement, required this.name, required this.settlementRepo});

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
            onPressed: () => settlementRepo.confirmSettlement(settlement.id),
          ),
        ],
      ),
    );
  }
}
