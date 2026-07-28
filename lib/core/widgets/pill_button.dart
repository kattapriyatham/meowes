import 'package:flutter/material.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';

/// Paper-theme pill button. Primary = ink fill + on-brand text; secondary =
/// a lifted card-tone fill with a hairline border. Both have a soft shadow.
class PillButton extends StatelessWidget {
  final String label;
  final bool primary;
  final VoidCallback? onTap;
  const PillButton({super.key, required this.label, required this.onTap, this.primary = true});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = primary
        ? t.brandSolid
        : Color.lerp(t.cardColor, Colors.white, isDark ? 0.14 : 0.6)!;
    final fg = primary ? t.onBrand : t.textPrimary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(30),
          border: primary ? null : Border.all(color: t.textPrimary.withValues(alpha: 0.08)),
          boxShadow: [BoxShadow(color: t.cardShadow, blurRadius: 14, offset: const Offset(0, 6))],
        ),
        child: Text(label, style: TextStyle(color: fg, fontSize: 15, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
