// lib/features/notifications/notifications_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: StreamBuilder<List<Friendship>>(
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
    );
  }
}

class _PendingRequestsList extends StatelessWidget {
  final FriendRepository friendRepo;
  final List<String> requesterIds;
  const _PendingRequestsList({required this.friendRepo, required this.requesterIds});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AppUser>>(
      future: friendRepo.getPublicProfiles(requesterIds),
      builder: (context, snapshot) {
        final names = {for (final p in snapshot.data ?? <AppUser>[]) p.id: p.name};
        return Column(
          children: [
            for (final id in requesterIds) ...[
              AppCard(
                child: Row(
                  children: [
                    AppAvatar(seed: id, label: names[id] ?? '...'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(names[id] ?? '...', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    TextButton(
                      onPressed: () => friendRepo.declineFriendRequest(id),
                      child: const Text('Decline', style: TextStyle(color: AppColors.owingText)),
                    ),
                    ElevatedButton(
                      onPressed: () => friendRepo.acceptFriendRequest(id),
                      child: const Text('Accept'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
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
    final fromUserIds = settlements.map((s) => s.fromUser).toSet().toList();
    return FutureBuilder<List<AppUser>>(
      future: friendRepo.getPublicProfiles(fromUserIds),
      builder: (context, snapshot) {
        final names = {for (final p in snapshot.data ?? <AppUser>[]) p.id: p.name};
        return Column(
          children: [
            for (final s in settlements) ...[
              AppCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${names[s.fromUser] ?? '...'} paid you',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '₹${(s.amountMinorUnits / 100).toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.owedText),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () => settlementRepo.confirmSettlement(s.id),
                      child: const Text('Confirm'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}
