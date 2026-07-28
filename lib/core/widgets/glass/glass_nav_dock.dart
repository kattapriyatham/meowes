import 'package:flutter/material.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/glass/glass_surface.dart';

class GlassNavDock extends StatelessWidget {
  const GlassNavDock({super.key, required this.currentIndex, required this.onTap});
  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _items = [
    (icon: Icons.home_outlined, label: 'Home'),
    (icon: Icons.people_outline, label: 'Friends'),
    (icon: Icons.grid_view_outlined, label: 'Groups'),
    (icon: Icons.show_chart, label: 'Activity'),
    (icon: Icons.person_outline, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
        child: GlassSurface(
          strong: true,
          radius: 26,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < _items.length; i++)
                IconButton(
                  tooltip: _items[i].label,
                  onPressed: () => onTap(i),
                  icon: Icon(
                    _items[i].icon,
                    color: i == currentIndex ? t.brandSolid : t.textMuted,
                    semanticLabel: _items[i].label,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
