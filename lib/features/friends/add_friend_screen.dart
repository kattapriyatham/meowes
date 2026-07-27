// lib/features/friends/add_friend_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/repositories/friend_repository.dart';
import 'package:meowes_app/models/app_user.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Add friend')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Phone number'),
              keyboardType: TextInputType.phone,
            ),
            ElevatedButton(
              onPressed: () async {
                final result = await repo.searchByPhone(_phoneController.text.trim());
                setState(() {
                  _found = result;
                  _searched = true;
                });
              },
              child: const Text('Search'),
            ),
            if (_searched && _found != null)
              ListTile(
                title: Text(_found!.name),
                trailing: ElevatedButton(
                  onPressed: () async {
                    await repo.sendFriendRequest(_found!.id);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: const Text('Send request'),
                ),
              ),
            if (_searched && _found == null)
              const Text('Not registered yet — share an invite link instead.'),
              // Invite-link generation reuses the group invite_code mechanism
              // from Task 9 and is wired as a share-sheet action, not a new
              // backend concept.
          ],
        ),
      ),
    );
  }
}
