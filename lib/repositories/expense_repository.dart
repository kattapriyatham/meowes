import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/models/expense.dart';
import 'package:meowes_app/models/expense_split.dart';
import 'package:meowes_app/models/friend_activity_item.dart';
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

    await _writeSplits(
      expenseId: expense.id,
      amountMinorUnits: amountMinorUnits,
      splitType: splitType,
      participantIds: participantIds,
      percentages: percentages,
      exactAmounts: exactAmounts,
    );

    return expense;
  }

  Future<void> editExpense({
    required String expenseId,
    required String description,
    required int amountMinorUnits,
    required SplitType splitType,
    required List<String> participantIds,
    Map<String, double>? percentages,
    Map<String, int>? exactAmounts,
  }) async {
    final me = _client.auth.currentUser!.id;
    await _client.from('expenses').update({
      'description': description,
      'amount': (amountMinorUnits / 100).toStringAsFixed(2),
      'edited_at': DateTime.now().toIso8601String(),
      'edited_by': me,
    }).eq('id', expenseId);

    await _client.from('expense_splits').delete().eq('expense_id', expenseId);

    await _writeSplits(
      expenseId: expenseId,
      amountMinorUnits: amountMinorUnits,
      splitType: splitType,
      participantIds: participantIds,
      percentages: percentages,
      exactAmounts: exactAmounts,
    );
  }

  Future<void> deleteExpense(String expenseId) async {
    await _client
        .from('expenses')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', expenseId);
  }

  Future<List<ExpenseSplit>> getExpenseSplits(String expenseId) async {
    final rows = await _client.from('expense_splits').select().eq('expense_id', expenseId);
    return rows.map(ExpenseSplit.fromJson).toList();
  }

  Future<List<FriendActivityItem>> getFriendActivity(String otherUserId) async {
    final rows = await _client.rpc('get_friend_activity', params: {'other_user': otherUserId});
    final results = rows is List<dynamic> ? rows : const <dynamic>[];
    final items = results
        .map((r) => FriendActivityItem.fromJson(r as Map<String, dynamic>))
        .toList();
    items.sort((a, b) => b.date.compareTo(a.date));
    return items;
  }

  Future<Expense> getExpenseById(String expenseId) async {
    final row = await _client.from('expenses').select().eq('id', expenseId).single();
    return Expense.fromJson(row);
  }

  Future<List<Expense>> getSharedExpenses(String otherUserId) async {
    final rows = await _client.rpc('get_shared_expenses', params: {'other_user': otherUserId});
    final results = rows is List<dynamic> ? rows : const <dynamic>[];
    final expenses = results.map((r) => Expense.fromJson(r as Map<String, dynamic>)).toList();
    expenses.sort((a, b) => b.expenseDate.compareTo(a.expenseDate));
    return expenses;
  }

  Stream<List<Expense>> watchExpenses({required String groupId}) {
    return _client
        .from('expenses')
        .stream(primaryKey: ['id'])
        .eq('group_id', groupId)
        .map((rows) {
      final expenses = rows.map(Expense.fromJson).where((e) => !e.isDeleted).toList();
      expenses.sort((a, b) => b.expenseDate.compareTo(a.expenseDate));
      return expenses;
    });
  }

  Future<void> _writeSplits({
    required String expenseId,
    required int amountMinorUnits,
    required SplitType splitType,
    required List<String> participantIds,
    Map<String, double>? percentages,
    Map<String, int>? exactAmounts,
  }) async {
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
          'expense_id': expenseId,
          'user_id': entry.key,
          'share_amount': (entry.value / 100).toStringAsFixed(2),
        },
    ]);
  }
}

final expenseRepositoryProvider = Provider<ExpenseRepository>(
  (ref) => ExpenseRepository(ref.watch(supabaseClientProvider)),
);
