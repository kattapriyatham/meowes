import 'package:flutter/material.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/glass/glass_surface.dart';

class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({super.key, this.title, this.leading, this.actions = const []});
  final String? title;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: GlassSurface(
          strong: true,
          radius: 20,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              if (leading != null) leading!,
              if (title != null)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(title!, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: t.textPrimary)),
                  ),
                )
              else
                const Spacer(),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}
