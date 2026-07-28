import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';

class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: const Alignment(0.2, -1),
          end: const Alignment(-0.2, 1),
          colors: [t.gradientTop, t.gradientBottom],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -40, right: -30,
            child: _Blob(color: t.blobIndigo, size: 240),
          ),
          Positioned(
            bottom: 80, left: -50,
            child: _Blob(color: t.blobTeal, size: 220),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
