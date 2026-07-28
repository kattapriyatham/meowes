// lib/features/settlements/settle_up_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/theme/app_typography.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/repositories/settlement_repository.dart';

final settlementRepositoryProvider = Provider<SettlementRepository>(
  (ref) => SettlementRepository(ref.watch(supabaseClientProvider)),
);

class SettleUpScreen extends ConsumerWidget {
  final String toUser;
  final int amountMinorUnits;
  final String? groupId;

  const SettleUpScreen({
    super.key,
    required this.toUser,
    required this.amountMinorUnits,
    this.groupId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final repo = ref.watch(settlementRepositoryProvider);
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
                  '₹${(amountMinorUnits / 100).toStringAsFixed(2)}',
                  style: moneyStyle(t.negative, size: 36),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: PillButton(
                    label: 'Mark as Paid',
                    primary: true,
                    onTap: () async {
                      await repo.markPaid(
                        toUser: toUser,
                        amountMinorUnits: amountMinorUnits,
                        groupId: groupId,
                      );
                      if (context.mounted) Navigator.of(context).pop();
                    },
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
