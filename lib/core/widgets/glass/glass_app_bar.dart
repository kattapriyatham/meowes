import 'package:flutter/material.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/soft_icon_button.dart';

/// Paper-theme header: a plain transparent bar with an ink title, an optional
/// boxed back button (auto when the route can pop), and trailing actions.
/// (Kept the GlassAppBar name so existing screens don't need import churn.)
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({super.key, this.title, this.leading, this.actions = const []});
  final String? title;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final lead = leading ??
        (Navigator.of(context).canPop()
            ? SoftIconButton(icon: Icons.arrow_back, onTap: () => Navigator.of(context).maybePop())
            : null);
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(
          children: [
            if (lead != null) ...[lead, const SizedBox(width: 12)],
            if (title != null)
              Expanded(
                child: Text(
                  title!,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 22,
                      ),
                ),
              )
            else
              const Spacer(),
            ...actions,
          ],
        ),
      ),
    );
  }
}
