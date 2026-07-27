// lib/features/settlements/settle_up_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
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
    final repo = ref.watch(settlementRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settle up')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🐾', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 16),
              Text(
                '₹${(amountMinorUnits / 100).toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: AppColors.owingText),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    await repo.markPaid(
                      toUser: toUser,
                      amountMinorUnits: amountMinorUnits,
                      groupId: groupId,
                    );
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: const Text('Mark as Paid'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
