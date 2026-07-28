import 'package:flutter/material.dart';
import 'package:meowes_app/core/a11y/accessibility.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';

class SkeletonLoader extends StatefulWidget {
  const SkeletonLoader({super.key, this.height = 16, this.width = double.infinity, this.radius = 8});
  final double height;
  final double width;
  final double radius;

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  bool _started = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final reduceMotion = motionReduced(context);
    if (!reduceMotion && !_started) {
      _started = true;
      _c.repeat(reverse: true);
    } else if (reduceMotion && _started) {
      _started = false;
      _c.stop();
    }
    final box = Container(
      height: widget.height,
      width: widget.width,
      decoration: BoxDecoration(color: t.glassStrongFill, borderRadius: BorderRadius.circular(widget.radius)),
    );
    if (reduceMotion) return Opacity(opacity: 0.5, child: box);
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 0.7).animate(_c),
      child: box,
    );
  }
}
