// lib/features/groups/create_group_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/async_action.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
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
    Group? group;
    final ok = await runAction(
      context,
      ref,
      notifyData: false,
      action: () async {
        group = await repo.createGroup(_nameController.text.trim());
      },
    );
    if (ok && mounted) setState(() => _created = group);
  }

  Future<void> _handleJoin(GroupRepository repo) async {
    Group? group;
    final ok = await runAction(
      context,
      ref,
      notifyData: false,
      errorMessage: (e) => e is StateError ? e.message : 'Could not join that group.',
      action: () async {
        group = await repo.joinByInviteCode(_codeController.text.trim());
      },
    );
    if (ok && mounted) setState(() => _created = group);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(groupRepositoryProvider);
    final t = Theme.of(context).extension<GlassTokens>()!;

    if (_created != null) {
      final group = _created!;
      return GlassScaffold(
        appBar: const GlassAppBar(title: 'Group created'),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(group.name, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: t.textPrimary)),
                const SizedBox(height: 20),
                const SectionHeader(title: 'Invite code'),
                const SizedBox(height: 12),
                SoftCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          group.inviteCode,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                            color: t.textPrimary,
                          ),
                        ),
                      ),
                      SoftIconButton(
                        icon: Icons.copy,
                        onTap: () => Clipboard.setData(ClipboardData(text: group.inviteCode)),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: PillButton(
                    label: 'Done',
                    onTap: () => Navigator.of(context).pop(group),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return GlassScaffold(
      appBar: const GlassAppBar(title: 'Create group'),
      body: SafeArea(
        child: Padding(
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
                  child: PillButton(
                    label: 'Join',
                    onTap: () => _handleJoin(repo),
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
                  child: PillButton(
                    label: 'Create',
                    onTap: () => _handleCreate(repo),
                  ),
                ),
              ],
            ],
          ),
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
    final t = Theme.of(context).extension<GlassTokens>()!;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? t.brandSolid : t.cardColor,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? t.onBrand : t.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
