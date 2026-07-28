import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/models/friend_activity_item.dart';
import 'package:meowes_app/repositories/expense_repository.dart';
import 'package:meowes_app/splitting/split_calculator.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockGoTrueClient extends Mock implements GoTrueClient {}
class MockQueryBuilder extends Mock implements SupabaseQueryBuilder {}

// PostgrestFilterBuilder implements Future, and mocktail's Mock cannot
// reliably stub then() (its onError named-argument shape doesn't match
// what Dart's await protocol actually passes). A hand-written Fake with a
// real then() implementation sidesteps that — Fake's noSuchMethod covers
// every other interface member this test never calls.
//
// The three-tier shape below (rather than one Fake reused at every level)
// is required, not stylistic: verified empirically against the installed
// postgrest package that insert(...).select() resolves via
// PostgrestTransformBuilder.select() (NOT PostgrestQueryBuilder.select()),
// which returns PostgrestTransformBuilder<PostgrestList> — a different
// generic instantiation than insert()'s own PostgrestFilterBuilder<PostgrestMap>
// return type — and .single() on that returns PostgrestTransformBuilder<PostgrestMap>.
// A single Fake class cannot satisfy all three signatures simultaneously.
class _FakeSingleRow extends Fake
    implements PostgrestTransformBuilder<PostgrestMap> {
  final PostgrestMap value;
  _FakeSingleRow(this.value);

  @override
  Future<U> then<U>(FutureOr<U> Function(PostgrestMap) onValue,
      {Function? onError}) {
    return Future.value(value).then(onValue, onError: onError);
  }
}

class _FakeListResult extends Fake
    implements PostgrestTransformBuilder<PostgrestList> {
  final PostgrestMap singleValue;
  _FakeListResult(this.singleValue);

  @override
  PostgrestTransformBuilder<PostgrestMap> single() => _FakeSingleRow(singleValue);
}

class _FakeInsertResult extends Fake
    implements PostgrestFilterBuilder<PostgrestMap> {
  final PostgrestMap value;
  _FakeInsertResult([this.value = const {}]);

  @override
  PostgrestTransformBuilder<PostgrestList> select([String columns = '*']) =>
      _FakeListResult(value);

  @override
  Future<U> then<U>(FutureOr<U> Function(PostgrestMap) onValue,
      {Function? onError}) {
    return Future.value(value).then(onValue, onError: onError);
  }
}

class _FakeFilterChain extends Fake implements PostgrestFilterBuilder<PostgrestList> {
  @override
  PostgrestFilterBuilder<PostgrestList> eq(String column, Object value) => this;

  @override
  Future<U> then<U>(FutureOr<U> Function(PostgrestList) onValue, {Function? onError}) {
    return Future.value(<Map<String, dynamic>>[]).then(onValue, onError: onError);
  }
}

// SupabaseClient.rpc returns a PostgrestFilterBuilder (a Future-like
// builder), not a plain Future — so a Fake with a real then() is needed
// to stub it, same pattern as the insert/select fakes above.
class _FakeRpcResult extends Fake implements PostgrestFilterBuilder<dynamic> {
  final dynamic value;
  _FakeRpcResult(this.value);

  @override
  Future<U> then<U>(FutureOr<U> Function(dynamic) onValue, {Function? onError}) {
    return Future.value(value).then(onValue, onError: onError);
  }
}

void main() {
  test('createExpense inserts expense then inserts splits from SplitCalculator', () async {
    final client = MockSupabaseClient();
    final auth = MockGoTrueClient();
    final expensesTable = MockQueryBuilder();
    final splitsTable = MockQueryBuilder();

    when(() => client.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(
      User(
        id: 'u1',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-07-27T00:00:00Z',
      ),
    );
    when(() => client.from('expenses')).thenAnswer((_) => expensesTable);
    when(() => client.from('expense_splits')).thenAnswer((_) => splitsTable);
    when(() => expensesTable.insert(any())).thenAnswer((_) => _FakeInsertResult({
          'id': 'e1',
          'group_id': null,
          'paid_by': 'u1',
          'description': 'Coffee',
          'amount': '100.00',
          'currency': 'INR',
          'expense_date': '2026-07-27',
          'created_at': '2026-07-27T10:00:00Z',
          'created_by': 'u1',
          'edited_at': null,
          'edited_by': null,
          'deleted_at': null,
        }));
    when(() => splitsTable.insert(any())).thenAnswer((_) => _FakeInsertResult());

    final repo = ExpenseRepository(client);
    final expense = await repo.createExpense(
      description: 'Coffee',
      amountMinorUnits: 10000,
      groupId: null,
      paidBy: 'u1',
      splitType: SplitType.equal,
      participantIds: ['u1', 'u2'],
      expenseDate: DateTime(2026, 7, 27),
    );

    expect(expense.id, 'e1');
    final captured = verify(() => splitsTable.insert(captureAny())).captured.single
        as List<Map<String, dynamic>>;
    expect(captured, containsAll([
      {'expense_id': 'e1', 'user_id': 'u1', 'share_amount': '50.00'},
      {'expense_id': 'e1', 'user_id': 'u2', 'share_amount': '50.00'},
    ]));
  });

  test('editExpense replaces old splits with a fresh SplitCalculator recompute', () async {
    final client = MockSupabaseClient();
    final auth = MockGoTrueClient();
    final expensesTable = MockQueryBuilder();
    final splitsTable = MockQueryBuilder();

    when(() => client.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(
      User(
        id: 'u1',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-07-27T00:00:00Z',
      ),
    );
    when(() => client.from('expenses')).thenAnswer((_) => expensesTable);
    when(() => client.from('expense_splits')).thenAnswer((_) => splitsTable);
    when(() => expensesTable.update(any())).thenAnswer((_) => _FakeFilterChain());
    when(() => splitsTable.delete()).thenAnswer((_) => _FakeFilterChain());
    when(() => splitsTable.insert(any())).thenAnswer((_) => _FakeInsertResult());

    final repo = ExpenseRepository(client);
    await repo.editExpense(
      expenseId: 'e1',
      description: 'Coffee (updated)',
      amountMinorUnits: 10000,
      splitType: SplitType.equal,
      participantIds: ['u1', 'u2'],
    );

    final captured = verify(() => splitsTable.insert(captureAny())).captured.single
        as List<Map<String, dynamic>>;
    expect(captured, containsAll([
      {'expense_id': 'e1', 'user_id': 'u1', 'share_amount': '50.00'},
      {'expense_id': 'e1', 'user_id': 'u2', 'share_amount': '50.00'},
    ]));
  });

  test('getFriendActivity calls the RPC and returns items sorted newest-first', () async {
    final client = MockSupabaseClient();
    when(() => client.rpc('get_friend_activity',
            params: {'other_user': 'friend-1'}))
        .thenAnswer((_) => _FakeRpcResult([
      {'kind': 'expense', 'ref_id': 'e1', 'name': 'Old', 'net': 100.0, 'activity_date': '2026-07-01'},
      {'kind': 'group', 'ref_id': 'g1', 'name': 'Trip', 'net': -50.0, 'activity_date': '2026-07-20'},
    ]));

    final repo = ExpenseRepository(client);
    final items = await repo.getFriendActivity('friend-1');

    expect(items.length, 2);
    expect(items.first.name, 'Trip'); // newest first
    expect(items.last.name, 'Old');
    expect(items.first.kind, FriendActivityKind.group);
  });
}
