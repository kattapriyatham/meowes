import 'package:flutter/material.dart';
import 'package:meowes_app/core/app_theme.dart';

class EmptyStateBox extends StatelessWidget {
  final IconData icon;
  final String message;

  const EmptyStateBox({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(
          children: [
            Icon(icon, color: AppColors.textMuted, size: 28),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
          ],
        ),
      );
}
