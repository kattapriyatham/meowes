// lib/features/moderation/report_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/async_action.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart' show friendRepositoryProvider;

const _reasons = <String, String>{
  'offensive': 'Offensive or hateful',
  'harassment': 'Harassment or bullying',
  'spam': 'Spam',
  'inappropriate': 'Inappropriate content',
  'other': 'Something else',
};

/// Opens the report sheet for a piece of content. [targetType] is
/// 'expense' | 'group' | 'user' | 'remind'; [targetId] is that row's id
/// (or the offending user's id for 'user' / 'remind').
Future<void> showReportSheet(
  BuildContext context,
  WidgetRef ref, {
  required String targetType,
  required String targetId,
  String? title,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReportSheet(targetType: targetType, targetId: targetId, title: title),
  );
}

class _ReportSheet extends ConsumerStatefulWidget {
  final String targetType;
  final String targetId;
  final String? title;
  const _ReportSheet({required this.targetType, required this.targetId, this.title});

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  String? _reason;
  final _details = TextEditingController();

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ok = await runAction(
      context,
      ref,
      notifyData: false,
      action: () => ref.read(friendRepositoryProvider).reportContent(
            targetType: widget.targetType,
            targetId: widget.targetId,
            reason: _reason!,
            details: _details.text,
          ),
      successMessage: "Report submitted — we'll review it within 24 hours.",
    );
    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Material(
      type: MaterialType.card,
      color: t.cardColor,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title ?? 'Report',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: t.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            "Tell us what's wrong. Our team reviews every report.",
            style: TextStyle(fontSize: 13, color: t.textSecondary),
          ),
          const SizedBox(height: 16),
          for (final entry in _reasons.entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              onTap: () => setState(() => _reason = entry.key),
              leading: Icon(
                _reason == entry.key
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: _reason == entry.key ? t.brandSolid : t.textMuted,
              ),
              title: Text(entry.value, style: TextStyle(color: t.textPrimary)),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _details,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'More detail (optional)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          PillButton(
            label: 'Submit report',
            primary: true,
            onTap: _reason == null ? null : _submit,
          ),
        ],
      ),
      ),
    );
  }
}
