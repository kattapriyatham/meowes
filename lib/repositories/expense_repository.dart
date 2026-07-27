import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/models/expense.dart';
import 'package:meowes_app/splitting/split_calculator.dart';

class ExpenseRepository {
  final SupabaseClient _client;
  ExpenseRepository(this._client);

  Future<Expense> createExpense({
    required String description,
    required int amountMinorUnits,
    String? groupId,
    required String paidBy,
    required SplitType splitType,
    required List<String> participantIds,
    Map<String, double>? percentages,
    Map<String, int>? exactAmounts,
    required DateTime expenseDate,
  }) async {
    final me = _client.auth.currentUser!.id;
    final row = await _client
        .from('expenses')
        .insert({
          'group_id': groupId,
          'paid_by': paidBy,
          'description': description,
          'amount': (amountMinorUnits / 100).toStringAsFixed(2),
          'currency': 'INR',
          'expense_date': expenseDate.toIso8601String().split('T').first,
          'created_by': me,
        })
        .select()
        .single();
    final expense = Expense.fromJson(row);

    final shares = SplitCalculator.calculate(
      totalMinorUnits: amountMinorUnits,
      type: splitType,
      participantIds: participantIds,
      percentages: percentages,
      exactAmounts: exactAmounts,
    );

    await _client.from('expense_splits').insert([
      for (final entry in shares.entries)
        {
          'expense_id': expense.id,
          'user_id': entry.key,
          'share_amount': (entry.value / 100).toStringAsFixed(2),
        },
    ]);

    return expense;
  }

  Future<void> editExpense({
    required String expenseId,
    required String description,
    required int amountMinorUnits,
  }) async {
    final me = _client.auth.currentUser!.id;
    await _client.from('expenses').update({
      'description': description,
      'amount': (amountMinorUnits / 100).toStringAsFixed(2),
      'edited_at': DateTime.now().toIso8601String(),
      'edited_by': me,
    }).eq('id', expenseId);
    // Re-splitting on edit reuses the same expense_splits insert path as
    // createExpense; a full re-split (delete old splits, insert new ones
    // via SplitCalculator) is called from expense_detail_screen.dart (Task 13).
  }

  Future<void> deleteExpense(String expenseId) async {
    await _client
        .from('expenses')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', expenseId);
  }
}
