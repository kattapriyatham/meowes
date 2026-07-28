// lib/features/profile/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/a11y/accessibility.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart' show friendRepositoryProvider;
import 'package:meowes_app/models/app_user.dart';

// Re-exported so screens/tests that only import this file (rather than the
// friend-add screen where it happens to be declared) can still reach the
// shared friendRepositoryProvider.
export 'package:meowes_app/features/friends/add_friend_screen.dart' show friendRepositoryProvider;

/// Profile tab: glass header with avatar/name, a settings card (currently
/// just the reduce-transparency accessibility toggle), and a sign-out
/// action.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    final friendRepo = ref.watch(friendRepositoryProvider);
    final me = client.auth.currentUser!.id;

    return GlassScaffold(
      appBar: const GlassAppBar(title: 'Profile'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          children: [
            FutureBuilder<AppUser?>(
              future: friendRepo.getMyProfile(),
              builder: (context, snapshot) {
                final loading = snapshot.connectionState == ConnectionState.waiting;
                final name = snapshot.data?.name;
                return _ProfileHeader(me: me, name: name, loading: loading);
              },
            ),
            const SizedBox(height: 16),
            GlassCard(
              padding: EdgeInsets.zero,
              child: Material(
                color: Colors.transparent,
                child: SwitchListTile(
                  title: const Text('Reduce transparency'),
                  value: ref.watch(reduceTransparencyProvider),
                  onChanged: (v) => ref.read(reduceTransparencyProvider.notifier).state = v,
                ),
              ),
            ),
            const SizedBox(height: 16),
            GlassButton(
              label: 'Sign out',
              secondary: true,
              onPressed: () => ref.read(supabaseClientProvider).auth.signOut(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final String me;
  final String? name;
  final bool loading;

  const _ProfileHeader({required this.me, required this.name, required this.loading});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return GlassCard(
      child: Row(
        children: [
          AppAvatar(seed: me, label: name, size: 56),
          const SizedBox(width: 16),
          Expanded(
            child: loading
                ? const SkeletonLoader(height: 18, width: 140)
                : Text(
                    name ?? 'Unknown',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: t.textPrimary),
                  ),
          ),
        ],
      ),
    );
  }
}
