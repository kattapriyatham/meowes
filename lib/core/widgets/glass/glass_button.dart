import 'package:flutter/material.dart';
import 'package:meowes_app/core/a11y/accessibility.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/glass/glass_surface.dart';

class GlassButton extends StatefulWidget {
  const GlassButton({super.key, required this.label, required this.onPressed, this.secondary = false});
  final String label;
  final VoidCallback? onPressed;
  final bool secondary;

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final content = Center(
      child: Text(widget.label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: widget.secondary ? t.textPrimary : t.onBrand, fontWeight: FontWeight.w600)),
    );
    final child = widget.secondary
        ? GlassSurface(radius: 14, padding: const EdgeInsets.symmetric(vertical: 14), child: content)
        : Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(gradient: t.brandGradient, borderRadius: BorderRadius.circular(14)),
            child: content,
          );
    final reduceMotion = motionReduced(context);
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: !reduceMotion && _down ? 0.98 : 1,
        duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 90),
        child: child,
      ),
    );
  }
}
