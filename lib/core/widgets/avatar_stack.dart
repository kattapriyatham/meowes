import 'package:flutter/material.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/widgets/app_avatar.dart';

/// A row of overlapping [AppAvatar]s (each painted over the previous one),
/// for showing a group's members at a glance. [seeds] and [labels] must be
/// the same length and in the same order.
class AvatarStack extends StatelessWidget {
  final List<String> seeds;
  final List<String> labels;
  final double size;
  final double overlap;

  const AvatarStack({
    super.key,
    required this.seeds,
    required this.labels,
    this.size = 36,
    this.overlap = 20,
  }) : assert(seeds.length == labels.length);

  @override
  Widget build(BuildContext context) {
    if (seeds.isEmpty) return const SizedBox.shrink();
    final width = size + overlap * (seeds.length - 1);
    return SizedBox(
      width: width,
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < seeds.length; i++)
            Positioned(
              left: overlap * i,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.cream, width: 2),
                ),
                child: AppAvatar(seed: seeds[i], label: labels[i], size: size),
              ),
            ),
        ],
      ),
    );
  }
}
