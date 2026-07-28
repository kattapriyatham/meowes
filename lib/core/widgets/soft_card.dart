import 'package:flutter/material.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';

/// Solid warm "paper" card: opaque [GlassTokens.cardColor] fill + a soft warm
/// drop shadow + large radius. The non-glass card style of the cream theme.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 28,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: t.cardColor,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(color: t.cardShadow, blurRadius: 28, offset: const Offset(0, 12)),
        ],
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(borderRadius: BorderRadius.circular(radius), onTap: onTap, child: card),
    );
  }
}
