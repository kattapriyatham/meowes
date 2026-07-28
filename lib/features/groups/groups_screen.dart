// lib/features/groups/groups_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

    return GlassScaffold(
      appBar: GlassAppBar(
        title: 'Groups',
        actions: [
          IconButton(
            tooltip: 'Create group',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          children: [
            StreamBuilder<List<Group>>(
              stream: groupRepo.watchMyGroups(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  final t = Theme.of(context).extension<GlassTokens>()!;
                  return Text(
                    'Something went wrong loading groups.',
                    style: TextStyle(color: t.negative),
                  );
                }

                final loading = !snapshot.hasData;
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

                final groups = snapshot.data ?? [];
                if (groups.isEmpty) {
                  return const EmptyStateBox(
                    icon: Icons.grid_view_outlined,
                    message: 'No groups yet. Create one to split with a crew.',
                  );
                }

                return GlassCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < groups.length; i++) ...[
                        if (i > 0) const _RowDivider(),
                        _GroupRow(group: groups[i], me: me, client: client),
                      ],
                    ],
                  ),
                );
              },
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
    return Divider(height: 1, thickness: 1, color: t.glassBorder, indent: 16, endIndent: 16);
  }
}

class _GroupRow extends StatelessWidget {
  final Group group;
  final String me;
  final SupabaseClient client;
  const _GroupRow({required this.group, required this.me, required this.client});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
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
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => GroupDetailScreen(groupId: group.id)),
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
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: t.textPrimary),
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
              children: const [
                SkeletonLoader(height: 14, width: 120),
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
