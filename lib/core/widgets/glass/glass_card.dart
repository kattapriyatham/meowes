import 'package:flutter/material.dart';
import 'package:meowes_app/core/widgets/glass/glass_surface.dart';

class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.disableBlur = false});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool disableBlur;

  @override
  Widget build(BuildContext context) {
    final surface = GlassSurface(padding: padding, disableBlur: disableBlur, child: child);
    if (onTap == null) return surface;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(borderRadius: BorderRadius.circular(24), onTap: onTap, child: surface),
    );
  }
}
