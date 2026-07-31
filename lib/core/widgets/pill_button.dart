import 'package:flutter/material.dart';
import 'package:meowes_app/core/a11y/accessibility.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';

/// Paper-theme pill button. Primary = ink fill + on-brand text; secondary =
/// a lifted card-tone fill with a hairline border. Both have a soft shadow.
/// Scales down slightly while pressed for tactile press feedback.
class PillButton extends StatefulWidget {
  final String label;
  final bool primary;
  final VoidCallback? onTap;

  /// Compact inline size (horizontal padding, smaller text) for row actions
  /// like Accept/Decline. Default is the full-width CTA size.
  final bool dense;
  const PillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = true,
    this.dense = false,
  });

  @override
  State<PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<PillButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap == null) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = widget.primary
        ? t.brandSolid
        : Color.lerp(t.cardColor, Colors.white, isDark ? 0.14 : 0.6)!;
    final fg = widget.primary ? t.onBrand : t.textPrimary;
    final reduceMotion = motionReduced(context);
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 100),
        child: Container(
          padding: widget.dense
              ? const EdgeInsets.symmetric(horizontal: 18, vertical: 10)
              : const EdgeInsets.symmetric(vertical: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(widget.dense ? 22 : 30),
            border: widget.primary
                ? null
                : Border.all(color: t.textPrimary.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: t.cardShadow,
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: fg,
              fontSize: widget.dense ? 13 : 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
