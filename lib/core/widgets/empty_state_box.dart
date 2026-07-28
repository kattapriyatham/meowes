import 'package:flutter/material.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/soft_card.dart';

class EmptyStateBox extends StatelessWidget {
  final IconData icon;
  final String message;

  const EmptyStateBox({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return SoftCard(
      child: Column(
        children: [
          Icon(icon, color: t.textMuted, size: 28),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, style: TextStyle(color: t.textMuted)),
        ],
      ),
    );
  }
}
