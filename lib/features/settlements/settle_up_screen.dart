import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('₹${(amountMinorUnits / 100).toStringAsFixed(2)}'),
            ElevatedButton(
              onPressed: () async {
                await repo.markPaid(
                  toUser: toUser,
                  amountMinorUnits: amountMinorUnits,
                  groupId: groupId,
                );
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('I paid this'),
            ),
          ],
        ),
      ),
    );
  }
}
