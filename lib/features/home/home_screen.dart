// lib/features/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart';
import 'package:meowes_app/features/groups/create_group_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    final friendsStream = ref.watch(friendRepositoryProvider).watchFriendships();
    final groupsStream = ref.watch(groupRepositoryProvider).watchMyGroups();

    return Scaffold(
      appBar: AppBar(title: const Text('Meowes')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Friends', style: TextStyle(fontSize: 20)),
          ),
          StreamBuilder(
            stream: friendsStream,
            builder: (context, snapshot) {
              final friendships = snapshot.data ?? [];
              final me = client.auth.currentUser!.id;
              return Column(
                children: [
                  for (final f in friendships.where((f) => f.status.name == 'accepted'))
                    _FriendBalanceTile(
                      friendUserId: f.userIdA == me ? f.userIdB : f.userIdA,
                    ),
                ],
              );
            },
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Groups', style: TextStyle(fontSize: 20)),
          ),
          StreamBuilder(
            stream: groupsStream,
            builder: (context, snapshot) {
              final groups = snapshot.data ?? [];
              return Column(
                children: [
                  for (final g in groups) ListTile(title: Text(g.name)),
                ],
              );
            },
          ),
        ],
      ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AddFriendScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.group_add),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendBalanceTile extends ConsumerWidget {
  final String friendUserId;
  const _FriendBalanceTile({required this.friendUserId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    final me = client.auth.currentUser!.id;
    return FutureBuilder(
      future: client.rpc('get_friend_balance', params: {
        'user_a': me,
        'user_b': friendUserId,
      }),
      builder: (context, snapshot) {
        final balance = (snapshot.data as num?)?.toDouble() ?? 0;
        return ListTile(
          title: Text(friendUserId),
          trailing: Text('₹${balance.toStringAsFixed(2)}'),
        );
      },
    );
  }
}
