import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:meowes_app/features/expenses/expense_detail_screen.dart';
import 'package:meowes_app/models/expense.dart';
import 'package:meowes_app/repositories/expense_repository.dart';

class MockExpenseRepository extends Mock implements ExpenseRepository {}

void main() {
  testWidgets('ExpenseDetailScreen shows Edit and Delete actions for a participant', (tester) async {
    final expense = Expense(
      id: 'e1',
      groupId: null,
      paidBy: 'u1',
      description: 'Coffee',
      amountMinorUnits: 10000,
      currency: 'INR',
      expenseDate: DateTime(2026, 7, 27),
      createdAt: DateTime(2026, 7, 27),
      createdBy: 'u1',
    );

    final mockRepo = MockExpenseRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expenseRepositoryProvider.overrideWithValue(mockRepo),
        ],
        child: MaterialApp(home: ExpenseDetailScreen(expense: expense)),
      ),
    );
    await tester.pump();

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Coffee'), findsOneWidget);
  });

  testWidgets('ExpenseDetailScreen shows an edited indicator when editedAt is set', (tester) async {
    final expense = Expense(
      id: 'e1',
      groupId: null,
      paidBy: 'u1',
      description: 'Coffee',
      amountMinorUnits: 10000,
      currency: 'INR',
      expenseDate: DateTime(2026, 7, 27),
      createdAt: DateTime(2026, 7, 27),
      createdBy: 'u1',
      editedAt: DateTime(2026, 7, 28),
      editedBy: 'u2',
    );

    final mockRepo = MockExpenseRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expenseRepositoryProvider.overrideWithValue(mockRepo),
        ],
        child: MaterialApp(home: ExpenseDetailScreen(expense: expense)),
      ),
    );
    await tester.pump();

    expect(find.text('Edited'), findsOneWidget);
  });
}
