import 'package:flutter/material.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  const SectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return Text(
      title,
      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: t.textPrimary),
    );
  }
}
