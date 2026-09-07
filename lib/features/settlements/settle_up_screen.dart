// lib/features/settlements/settle_up_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/theme/app_typography.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/repositories/settlement_repository.dart';

final settlementRepositoryProvider = Provider<SettlementRepository>(
  (ref) => SettlementRepository(ref.watch(supabaseClientProvider)),
);

class SettleUpScreen extends ConsumerStatefulWidget {
  final String toUser;
  final int amountMinorUnits;
  final String? groupId;

  /// Friend's display name, only for the confirmation message on the way out.
  final String? toUserName;

  const SettleUpScreen({
    super.key,
    required this.toUser,
    required this.amountMinorUnits,
    this.groupId,
    this.toUserName,
  });

  @override
  ConsumerState<SettleUpScreen> createState() => _SettleUpScreenState();
}

class _SettleUpScreenState extends ConsumerState<SettleUpScreen> {
  bool _submitting = false;

  Future<void> _markPaid() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(settlementRepositoryProvider).markPaid(
            toUser: widget.toUser,
            amountMinorUnits: widget.amountMinorUnits,
            groupId: widget.groupId,
          );
      // Refresh the one-shot FutureBuilder screens revealed by the pop.
      // The payer's balance won't move until the recipient confirms
      // (get_friend_balance only counts confirmed settlements), so the
      // SnackBar is the only signal the payer gets that it worked.
      notifyDataChanged(ref);
      if (!mounted) return;
      navigator.pop();
      final who = widget.toUserName ?? 'your friend';
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text('Payment recorded — waiting for $who to confirm')),
        );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text("Couldn't record the payment. Try again.")),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return GlassScaffold(
      appBar: const GlassAppBar(title: 'Settle up'),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.handshake_outlined, size: 40, color: t.textSecondary),
                const SizedBox(height: 16),
                Text(
                  '₹${(widget.amountMinorUnits / 100).toStringAsFixed(2)}',
                  style: moneyStyle(t.negative, size: 36),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: _submitting
                      ? Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: t.textSecondary,
                            ),
                          ),
                        )
                      : PillButton(
                          label: 'Mark as Paid',
                          primary: true,
                          onTap: _markPaid,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
