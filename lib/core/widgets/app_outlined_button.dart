// lib/core/widgets/app_outlined_button.dart
import 'package:flutter/material.dart';

/// A secondary (outlined) button in a given accent [color] — the coral/
/// dark/danger variant used wherever a screen needs a de-emphasized action
/// next to a primary `ElevatedButton` (Settle Up, Apple sign-in, Edit/Delete).
class AppOutlinedButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  const AppOutlinedButton({
    super.key,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
      child: Text(label),
    );
  }
}
