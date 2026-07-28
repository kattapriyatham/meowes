import 'package:flutter/material.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';

/// Boxed soft icon button (cream tile + soft shadow) used for the app-bar
/// bell / back affordances in the paper theme.
class SoftIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  const SoftIconButton({super.key, required this.icon, required this.onTap, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: t.cardColor,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [BoxShadow(color: t.cardShadow, blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: Icon(icon, color: t.textPrimary, size: 22),
      ),
    );
  }
}
