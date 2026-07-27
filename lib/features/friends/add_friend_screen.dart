// lib/features/friends/add_friend_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/models/app_user.dart';
import 'package:meowes_app/models/friendship.dart';
import 'package:meowes_app/repositories/friend_repository.dart';

final friendRepositoryProvider = Provider<FriendRepository>(
  (ref) => FriendRepository(ref.watch(supabaseClientProvider)),
);

class AddFriendScreen extends ConsumerStatefulWidget {
  const AddFriendScreen({super.key});

  @override
  ConsumerState<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends ConsumerState<AddFriendScreen> {
  final _phoneController = TextEditingController();
  AppUser? _found;
  bool _searched = false;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(friendRepositoryProvider);
    final me = ref.watch(supabaseClientProvider).auth.currentUser!.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Add friend')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          StreamBuilder<List<Friendship>>(
            stream: repo.watchFriendships(),
            builder: (context, snapshot) {
              final friendIds = (snapshot.data ?? [])
                  .where((f) => f.status == FriendshipStatus.accepted)
                  .map((f) => f.userIdA == me ? f.userIdB : f.userIdA)
                  .toList();
              if (friendIds.isEmpty) return const SizedBox.shrink();
              return FutureBuilder<List<AppUser>>(
                future: repo.getPublicProfiles(friendIds),
                builder: (context, profileSnapshot) {
                  final profiles = profileSnapshot.data ?? [];
                  if (profiles.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(title: 'Recent'),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 76,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: profiles.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 16),
                          itemBuilder: (context, i) => Column(
                            children: [
                              AppAvatar(seed: profiles[i].id, label: profiles[i].name, size: 48),
                              const SizedBox(height: 4),
                              SizedBox(
                                width: 56,
                                child: Text(
                                  profiles[i].name,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  );
                },
              );
            },
          ),
          const SectionHeader(title: 'Search by phone'),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            decoration: const InputDecoration(labelText: 'Phone number'),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                final result = await repo.searchByPhone(_phoneController.text.trim());
                setState(() {
                  _found = result;
                  _searched = true;
                });
              },
              child: const Text('Search'),
            ),
          ),
          if (_searched && _found != null) ...[
            const SizedBox(height: 16),
            AppCard(
              child: Row(
                children: [
                  AppAvatar(seed: _found!.id, label: _found!.name),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_found!.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                  ElevatedButton(
                    onPressed: () async {
                      await repo.sendFriendRequest(_found!.id);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    child: const Text('Send request'),
                  ),
                ],
              ),
            ),
          ],
          if (_searched && _found == null) ...[
            const SizedBox(height: 16),
            const Text(
              'Not registered yet — share an invite link instead.',
              style: TextStyle(color: AppColors.textMuted),
            ),
            // Invite-link generation reuses the group invite_code mechanism
            // from Task 9 and is wired as a share-sheet action, not a new
            // backend concept.
          ],
        ],
      ),
    );
  }
}
