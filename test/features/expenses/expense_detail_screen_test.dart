import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:meowes_app/features/expenses/expense_detail_screen.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart';
import 'package:meowes_app/models/expense.dart';
import 'package:meowes_app/models/expense_split.dart';
import 'package:meowes_app/repositories/expense_repository.dart';
import 'package:meowes_app/repositories/friend_repository.dart';

class MockExpenseRepository extends Mock implements ExpenseRepository {}
class MockFriendRepository extends Mock implements FriendRepository {}
class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockGoTrueClient extends Mock implements GoTrueClient {}

SupabaseClient _mockClient() {
  final client = MockSupabaseClient();
  final auth = MockGoTrueClient();
  when(() => client.auth).thenReturn(auth);
  when(() => auth.currentUser).thenReturn(User(
    id: 'me', appMetadata: const {}, userMetadata: const {},
    aud: 'authenticated', createdAt: '2026-07-27T00:00:00Z',
  ));
  return client;
}

Expense _expense() => Expense(
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

    final mockExpenseRepo = MockExpenseRepository();
    final mockFriendRepo = MockFriendRepository();
    when(() => mockExpenseRepo.getExpenseSplits(any())).thenAnswer((_) async => []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(_mockClient()),
          expenseRepositoryProvider.overrideWithValue(mockExpenseRepo),
          friendRepositoryProvider.overrideWithValue(mockFriendRepo),
        ],
        child: MaterialApp(theme: AppTheme.light, home: ExpenseDetailScreen(expense: expense)),
      ),
    );
    await tester.pump();

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Coffee'), findsOneWidget);
  });

  testWidgets('ExpenseDetailScreen shows who paid and when it was added', (tester) async {
    final expense = Expense(
      id: 'e1', groupId: null, paidBy: 'me', description: 'Coffee',
      amountMinorUnits: 10000, currency: 'INR',
      expenseDate: DateTime(2020, 7, 20), createdAt: DateTime(2020, 7, 20, 14, 30),
      createdBy: 'me',
    );
    final mockExpenseRepo = MockExpenseRepository();
    final mockFriendRepo = MockFriendRepository();
    when(() => mockExpenseRepo.getExpenseSplits(any())).thenAnswer((_) async => []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(_mockClient()),
          expenseRepositoryProvider.overrideWithValue(mockExpenseRepo),
          friendRepositoryProvider.overrideWithValue(mockFriendRepo),
        ],
        child: MaterialApp(theme: AppTheme.light, home: ExpenseDetailScreen(expense: expense)),
      ),
    );
    await tester.pump();

    expect(find.text('Paid by You'), findsOneWidget);
    expect(find.text('Added 20 Jul 2020, 2:30 PM'), findsOneWidget);
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

    final mockExpenseRepo = MockExpenseRepository();
    final mockFriendRepo = MockFriendRepository();
    when(() => mockExpenseRepo.getExpenseSplits(any())).thenAnswer((_) async => []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(_mockClient()),
          expenseRepositoryProvider.overrideWithValue(mockExpenseRepo),
          friendRepositoryProvider.overrideWithValue(mockFriendRepo),
        ],
        child: MaterialApp(theme: AppTheme.light, home: ExpenseDetailScreen(expense: expense)),
      ),
    );
    await tester.pump();

    expect(find.text('Edited'), findsOneWidget);
  });

  testWidgets('Delete asks for confirmation and only deletes after confirming',
      (tester) async {
    final expense = _expense();
    final mockExpenseRepo = MockExpenseRepository();
    final mockFriendRepo = MockFriendRepository();
    when(() => mockExpenseRepo.getExpenseById(any())).thenAnswer((_) async => expense);
    when(() => mockExpenseRepo.getExpenseSplits(any()))
        .thenAnswer((_) async => <ExpenseSplit>[]);
    when(() => mockExpenseRepo.deleteExpense(any())).thenAnswer((_) async {});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(_mockClient()),
          expenseRepositoryProvider.overrideWithValue(mockExpenseRepo),
          friendRepositoryProvider.overrideWithValue(mockFriendRepo),
        ],
        child: MaterialApp(theme: AppTheme.light, home: ExpenseDetailScreen(expense: expense)),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Delete'));
    await tester.pump();

    // Dialog is up; nothing deleted yet.
    expect(find.text('Delete expense?'), findsOneWidget);
    verifyNever(() => mockExpenseRepo.deleteExpense(any()));

    // Cancel -> still nothing.
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    verifyNever(() => mockExpenseRepo.deleteExpense(any()));

    // Delete -> confirm -> repo call happens.
    await tester.tap(find.text('Delete'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pump();
    await tester.pump();
    verify(() => mockExpenseRepo.deleteExpense('e1')).called(1);
  });
}
