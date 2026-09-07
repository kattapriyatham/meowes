import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart' show friendRepositoryProvider;
import 'package:meowes_app/models/app_user.dart';
import 'package:meowes_app/repositories/friend_repository.dart';

/// Pushed when the app is opened via a `meowes://invite/<code>` link (see
/// the deep-link handling in `lib/main.dart`). Redeems the code immediately
/// on open — there's nothing else for this screen to do.
class JoinByInviteScreen extends ConsumerStatefulWidget {
  const JoinByInviteScreen({super.key, required this.inviteCode});
  final String inviteCode;

  @override
  ConsumerState<JoinByInviteScreen> createState() => _JoinByInviteScreenState();
}

enum _Outcome { loading, success, invalid, self }

class _JoinByInviteScreenState extends ConsumerState<JoinByInviteScreen> {
  _Outcome _outcome = _Outcome.loading;
  AppUser? _newFriend;

  @override
  void initState() {
    super.initState();
    _join();
  }

  Future<void> _join() async {
    try {
      final friend = await ref.read(friendRepositoryProvider).joinByInviteCode(widget.inviteCode);
      if (!mounted) return;
      setState(() {
        _newFriend = friend;
        _outcome = _Outcome.success;
      });
    } on CannotFriendSelfException {
      if (mounted) setState(() => _outcome = _Outcome.self);
    } on InvalidInviteCodeException {
      if (mounted) setState(() => _outcome = _Outcome.invalid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;

    return GlassScaffold(
      appBar: const GlassAppBar(title: 'Invite'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: switch (_outcome) {
              _Outcome.loading => const CircularProgressIndicator(),
              _Outcome.success => _Result(
                  icon: Icons.celebration,
                  iconColor: t.positive,
                  message: "You're now friends with ${_newFriend!.name}!",
                ),
              _Outcome.self => _Result(
                  icon: Icons.info_outline,
                  iconColor: t.textSecondary,
                  message: "That's your own invite link.",
                ),
              _Outcome.invalid => _Result(
                  icon: Icons.link_off,
                  iconColor: t.negative,
                  message: 'This invite link is no longer valid.',
                ),
            },
          ),
        ),
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.icon, required this.iconColor, required this.message});
  final IconData icon;
  final Color iconColor;
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 56, color: iconColor),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: t.textPrimary),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: PillButton(
            label: 'Done',
            primary: true,
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }
}
