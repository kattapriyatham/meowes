import 'package:flutter/material.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/glass/glass_surface.dart';

class GlassNavDock extends StatelessWidget {
  const GlassNavDock({super.key, required this.currentIndex, required this.onTap});
  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _items = [
    (icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home'),
    (icon: Icons.pets_outlined, activeIcon: Icons.pets, label: 'Pet'),
    (icon: Icons.people_outline, activeIcon: Icons.people, label: 'Friends'),
    (icon: Icons.grid_view_outlined, activeIcon: Icons.grid_view, label: 'Groups'),
    (icon: Icons.show_chart, activeIcon: Icons.show_chart, label: 'Activity'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: GlassSurface(
          strong: true,
          radius: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < _items.length; i++)
                Tooltip(
                  message: _items[i].label,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onTap(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            i == currentIndex ? _items[i].activeIcon : _items[i].icon,
                            color: i == currentIndex ? t.brandSolid : t.textMuted,
                            size: 24,
                            semanticLabel: _items[i].label,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _items[i].label,
                            style: TextStyle(
                              fontSize: 11,
                              color: i == currentIndex ? t.textPrimary : t.textMuted,
                              fontWeight: i == currentIndex ? FontWeight.w600 : FontWeight.w500,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
