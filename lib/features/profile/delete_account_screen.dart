// lib/features/profile/delete_account_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/async_action.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/auth/sign_in_screen.dart';

/// App Store Guideline 5.1.1(v) / Play account-deletion: a user can
/// permanently delete their account from inside the app. Backed by the
/// `delete_my_account` RPC (see
/// supabase/migrations/20260901120000_account_deletion.sql).
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _controller = TextEditingController();
  static const _phrase = 'DELETE';

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _confirmed => _controller.text.trim().toUpperCase() == _phrase;

  Future<void> _delete() async {
    final ok = await runAction(
      context,
      ref,
      notifyData: false,
      action: () => ref.read(authRepositoryProvider).deleteAccount(),
    );
    if (ok && mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SignInScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return GlassScaffold(
      appBar: const GlassAppBar(title: 'Delete account'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Icon(Icons.warning_amber_rounded, size: 40, color: t.negative),
            const SizedBox(height: 16),
            Text(
              'This permanently deletes your Meowes account. It cannot be undone.',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            _Bullets(
              title: 'Deleted right away',
              color: t.negative,
              items: const [
                'Your profile, name and phone number',
                'Your cat, its coins, items and memories',
                'Your friends list and group memberships',
                'Settlements no one has confirmed yet',
                'Your sign-in — you cannot log back in',
              ],
            ),
            const SizedBox(height: 16),
            _Bullets(
              title: 'Kept for the people you shared with',
              color: t.textSecondary,
              items: const [
                'Past shared expenses and confirmed settlements stay on '
                    'your friends’ accounts so their balances still add '
                    'up — they show as "Deleted user".',
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Type $_phrase to confirm',
              style: TextStyle(color: t.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: _phrase),
            ),
            const SizedBox(height: 20),
            PillButton(
              label: 'Delete my account',
              primary: true,
              onTap: _confirmed ? _delete : null,
            ),
            const SizedBox(height: 12),
            PillButton(
              label: 'Cancel',
              primary: false,
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bullets extends StatelessWidget {
  final String title;
  final Color color;
  final List<String> items;
  const _Bullets({required this.title, required this.color, required this.items});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w700, color: color),
        ),
        const SizedBox(height: 8),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: TextStyle(color: t.textSecondary)),
                Expanded(
                  child: Text(
                    item,
                    style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
