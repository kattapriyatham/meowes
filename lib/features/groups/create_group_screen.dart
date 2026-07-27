import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/repositories/group_repository.dart';

final groupRepositoryProvider = Provider<GroupRepository>(
  (ref) => GroupRepository(ref.watch(supabaseClientProvider)),
);

class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _nameController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(groupRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Create group')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Group name'),
            ),
            ElevatedButton(
              onPressed: () async {
                final group = await repo.createGroup(_nameController.text.trim());
                if (context.mounted) Navigator.of(context).pop(group);
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}
