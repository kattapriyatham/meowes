// lib/features/notifications/notifications_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/theme/app_typography.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart' show friendRepositoryProvider;
import 'package:meowes_app/features/settlements/settle_up_screen.dart' show settlementRepositoryProvider;
import 'package:meowes_app/models/app_user.dart';
import 'package:meowes_app/models/friendship.dart';
import 'package:meowes_app/models/settlement.dart';
import 'package:meowes_app/repositories/friend_repository.dart';
import 'package:meowes_app/repositories/settlement_repository.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    final friendRepo = ref.watch(friendRepositoryProvider);
    final settlementRepo = ref.watch(settlementRepositoryProvider);
    final me = client.auth.currentUser!.id;

    return GlassScaffold(
      appBar: const GlassAppBar(title: 'Notifications'),
      body: SafeArea(
        child: StreamBuilder<List<Friendship>>(
          stream: friendRepo.watchFriendships(),
          builder: (context, friendshipSnapshot) {
            final pendingRequesterIds = (friendshipSnapshot.data ?? [])
                .where((f) => f.status == FriendshipStatus.pending && f.requestedBy != me)
                .map((f) => f.userIdA == me ? f.userIdB : f.userIdA)
                .toList();

            return StreamBuilder<List<Settlement>>(
              stream: settlementRepo.watchPendingForMe(),
              builder: (context, settlementSnapshot) {
                final settlements = settlementSnapshot.data ?? [];

                if (pendingRequesterIds.isEmpty && settlements.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: EmptyStateBox(
                      icon: Icons.notifications_none,
                      message: 'Nothing needs your attention right now.',
                    ),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (pendingRequesterIds.isNotEmpty) ...[
                      const SectionHeader(title: 'Friend requests'),
                      const SizedBox(height: 12),
                      _PendingRequestsList(friendRepo: friendRepo, requesterIds: pendingRequesterIds),
                      const SizedBox(height: 24),
                    ],
                    if (settlements.isNotEmpty) ...[
                      const SectionHeader(title: 'Settlements to confirm'),
                      const SizedBox(height: 12),
                      _PendingSettlementsList(
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
      ),
    );
  }
}

class _PendingRequestsList extends StatelessWidget {
  final FriendRepository friendRepo;
  final List<String> requesterIds;
  const _PendingRequestsList({required this.friendRepo, required this.requesterIds});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return FutureBuilder<List<AppUser>>(
      future: friendRepo.getPublicProfiles(requesterIds),
      builder: (context, snapshot) {
        final names = {for (final p in snapshot.data ?? <AppUser>[]) p.id: p.name};
        return SoftCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < requesterIds.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    children: [
                      AppAvatar(seed: requesterIds[i], label: names[requesterIds[i]] ?? '...'),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          names[requesterIds[i]] ?? '...',
                          style: TextStyle(fontWeight: FontWeight.w600, color: t.textPrimary),
                        ),
                      ),
                      PillButton(
                        label: 'Decline',
                        primary: false,
                        onTap: () => friendRepo.declineFriendRequest(requesterIds[i]),
                      ),
                      const SizedBox(width: 8),
                      PillButton(
                        label: 'Accept',
                        primary: true,
                        onTap: () => friendRepo.acceptFriendRequest(requesterIds[i]),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PendingSettlementsList extends StatelessWidget {
  final FriendRepository friendRepo;
  final SettlementRepository settlementRepo;
  final List<Settlement> settlements;
  const _PendingSettlementsList({
    required this.friendRepo,
    required this.settlementRepo,
    required this.settlements,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final fromUserIds = settlements.map((s) => s.fromUser).toSet().toList();
    return FutureBuilder<List<AppUser>>(
      future: friendRepo.getPublicProfiles(fromUserIds),
      builder: (context, snapshot) {
        final names = {for (final p in snapshot.data ?? <AppUser>[]) p.id: p.name};
        return SoftCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < settlements.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${names[settlements[i].fromUser] ?? '...'} paid you',
                          style: TextStyle(fontWeight: FontWeight.w600, color: t.textPrimary),
                        ),
                      ),
                      Text(
                        '₹${(settlements[i].amountMinorUnits / 100).toStringAsFixed(2)}',
                        style: moneyStyle(t.positive),
                      ),
                      const SizedBox(width: 12),
                      PillButton(
                        label: 'Confirm',
                        primary: true,
                        onTap: () => settlementRepo.confirmSettlement(settlements[i].id),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
