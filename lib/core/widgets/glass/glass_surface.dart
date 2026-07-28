import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/a11y/accessibility.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';

class GlassSurface extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final border = strong ? t.glassStrongBorder : t.glassBorder;
    final radiusGeo = BorderRadius.circular(radius);
    final userReduceTransparency = ref.watch(reduceTransparencyProvider);
    final effectiveDisableBlur = disableBlur || glassDisabled(context, userReduceTransparency: userReduceTransparency);

    if (effectiveDisableBlur) {
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
              stops: const [0.0, 0.18],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
