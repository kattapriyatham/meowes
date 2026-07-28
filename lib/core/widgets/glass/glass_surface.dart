import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 24,
    this.strong = false,
    this.disableBlur = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool strong;
  final bool disableBlur;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final border = strong ? t.glassStrongBorder : t.glassBorder;
    final radiusGeo = BorderRadius.circular(radius);

    if (disableBlur) {
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          color: t.solidFallback,
          borderRadius: radiusGeo,
          border: Border.all(color: border, width: 1),
        ),
        child: child,
      );
    }

    return ClipRRect(
      borderRadius: radiusGeo,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: strong ? t.blurStrong : t.blurCard,
          sigmaY: strong ? t.blurStrong : t.blurCard,
        ),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: strong ? t.glassStrongFill : t.glassFill,
            borderRadius: radiusGeo,
            border: Border.all(color: border, width: 1),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [t.glassSheen, Colors.transparent],
              stops: const [0.0, 0.45],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
