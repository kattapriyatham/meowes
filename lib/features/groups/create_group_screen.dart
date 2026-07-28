// lib/features/groups/create_group_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/models/group.dart';
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
  final _codeController = TextEditingController();
  bool _isJoinMode = false;
  Group? _created;

  Future<void> _handleCreate(GroupRepository repo) async {
    final group = await repo.createGroup(_nameController.text.trim());
    if (!mounted) return;
    setState(() => _created = group);
  }

  Future<void> _handleJoin(GroupRepository repo) async {
    try {
      final group = await repo.joinByInviteCode(_codeController.text.trim());
      if (!mounted) return;
      setState(() => _created = group);
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(groupRepositoryProvider);

    if (_created != null) {
      final group = _created!;
      return Scaffold(
        appBar: AppBar(title: const Text('Group created')),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(group.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),
              const SectionHeader(title: 'Invite code'),
              const SizedBox(height: 12),
              AppCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        group.inviteCode,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 1.2),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, color: AppColors.coral),
                      onPressed: () => Clipboard.setData(ClipboardData(text: group.inviteCode)),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(group),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Create group')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _ModeTab(
                    label: 'Create',
                    selected: !_isJoinMode,
                    onTap: () => setState(() => _isJoinMode = false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ModeTab(
                    label: 'Join',
                    selected: _isJoinMode,
                    onTap: () => setState(() => _isJoinMode = true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_isJoinMode) ...[
              TextField(
                controller: _codeController,
                decoration: const InputDecoration(labelText: 'Invite code'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _handleJoin(repo),
                  child: const Text('Join'),
                ),
              ),
            ] else ...[
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Group name'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _handleCreate(repo),
                  child: const Text('Create'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModeTab({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.coral : Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textDark,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
