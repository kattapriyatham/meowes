import 'package:flutter/material.dart';
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
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 0.7).animate(_c),
      child: Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(color: t.glassStrongFill, borderRadius: BorderRadius.circular(widget.radius)),
      ),
    );
  }
}
