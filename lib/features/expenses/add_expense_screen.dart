import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/repositories/expense_repository.dart';
import 'package:meowes_app/splitting/split_calculator.dart';

final expenseRepositoryProvider = Provider<ExpenseRepository>(
  (ref) => ExpenseRepository(ref.watch(supabaseClientProvider)),
);

class AddExpenseScreen extends ConsumerStatefulWidget {
  final String? groupId;
  final List<String> participantIds;

  const AddExpenseScreen({super.key, this.groupId, required this.participantIds});

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  SplitType _splitType = SplitType.equal;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(expenseRepositoryProvider);
    final me = ref.watch(supabaseClientProvider).auth.currentUser!.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Add expense')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            TextField(
              controller: _amountController,
              decoration: const InputDecoration(labelText: 'Amount'),
              keyboardType: TextInputType.number,
            ),
            DropdownButton<SplitType>(
              value: _splitType,
              items: SplitType.values
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                  .toList(),
              onChanged: (t) => setState(() => _splitType = t!),
            ),
            ElevatedButton(
              onPressed: () async {
                final amountMinorUnits =
                    (double.parse(_amountController.text) * 100).round();
                await repo.createExpense(
                  description: _descriptionController.text.trim(),
                  amountMinorUnits: amountMinorUnits,
                  groupId: widget.groupId,
                  paidBy: me,
                  splitType: _splitType,
                  participantIds: widget.participantIds,
                  expenseDate: DateTime.now(),
                );
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
