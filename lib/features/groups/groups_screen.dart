// lib/features/groups/groups_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/groups/create_group_screen.dart';
import 'package:meowes_app/features/groups/group_detail_screen.dart';
import 'package:meowes_app/models/group.dart';

/// Groups tab: the user's groups with per-group net balances. The groups
/// stream and the `get_group_debts` net computation are lifted verbatim from
/// `home_screen.dart`'s `_GroupTile` so results are identical to the Home
/// tab's groups section; only the presentation here is glass.
class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    final groupRepo = ref.watch(groupRepositoryProvider);
    final me = client.auth.currentUser!.id;
    final t = Theme.of(context).extension<GlassTokens>()!;

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/groups-hero.png',
                key: const Key('groups-hero-image'),
                excludeFromSemantics: true,
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
                      Colors.black.withValues(alpha: 0.10),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.10),
                    ],
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
                    const Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Groups',
                            style: TextStyle(
                              color: AppColors.textDark,
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Share more, keep it simple',
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
                        tooltip: 'Create group',
                        icon: Icon(
                          Icons.group_add_outlined,
                          color: t.textPrimary,
                        ),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const CreateGroupScreen(),
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
                key: const Key('groups-scroll-sheet'),
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
                        child: Center(
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
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 132),
                        sliver: SliverToBoxAdapter(
                          child: StreamBuilder<List<Group>>(
                            stream: groupRepo.watchMyGroups(),
                            builder: (context, snapshot) {
                              if (snapshot.hasError) {
                                return Text(
                                  'Something went wrong loading groups.',
                                  style: TextStyle(color: t.negative),
                                );
                              }

                              if (!snapshot.hasData) {
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

                              final groups = snapshot.data ?? [];
                              if (groups.isEmpty) {
                                return const EmptyStateBox(
                                  icon: Icons.grid_view_outlined,
                                  message:
                                      'No groups yet. Create one to split with a crew.',
                                );
                              }

                              return GlassCard(
                                padding: EdgeInsets.zero,
                                child: Column(
                                  children: [
                                    for (var i = 0; i < groups.length; i++) ...[
                                      if (i > 0) const _RowDivider(),
                                      _GroupRow(
                                        group: groups[i],
                                        me: me,
                                        client: client,
                                      ),
                                    ],
                                  ],
                                ),
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

class _GroupRow extends StatelessWidget {
  final Group group;
  final String me;
  final SupabaseClient client;
  const _GroupRow({
    required this.group,
    required this.me,
    required this.client,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return FutureBuilder(
      future: client.rpc(
        'get_group_debts',
        params: {'target_group_id': group.id},
      ),
      builder: (context, snapshot) {
        final debts = (snapshot.data as List<dynamic>?) ?? [];
        var net = 0.0;
        for (final d in debts) {
          final amount = double.tryParse(d['amount'].toString()) ?? 0;
          if (d['to_user'] == me) net += amount;
          if (d['from_user'] == me) net -= amount;
        }
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GroupDetailScreen(groupId: group.id),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  AppAvatar(seed: group.id, icon: Icons.grid_view_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      group.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  BalanceAmount(balance: net),
                ],
              ),
            ),
          ),
        );
      },
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
              children: const [SkeletonLoader(height: 14, width: 120)],
            ),
          ),
          const SizedBox(width: 12),
          const SkeletonLoader(height: 14, width: 50),
        ],
      ),
    );
  }
}
