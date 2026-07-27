import 'package:flutter/material.dart';
import 'package:meowes_app/core/app_theme.dart';

/// Circular avatar with a deterministic color from [seed]. Shows the first
/// letter of [label] if given, otherwise [icon] (defaults to a person icon).
class AppAvatar extends StatelessWidget {
  final String seed;
  final String? label;
  final IconData? icon;
  final double size;

  const AppAvatar({
    super.key,
    required this.seed,
    this.label,
    this.icon,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.avatarFor(seed),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: label != null && label!.isNotEmpty
          ? Text(
              label![0].toUpperCase(),
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.4,
              ),
            )
          : Icon(icon ?? Icons.person, color: Colors.white, size: size * 0.5),
    );
  }
}
