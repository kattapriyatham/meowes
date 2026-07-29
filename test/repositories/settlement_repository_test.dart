import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/repositories/settlement_repository.dart';

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

// Fake for a single-row RPC result (confirm_settlement_and_award_coins
// returns `settlements`, i.e. a single row), modeled on
// pet_repository_test.dart's _FakeRpcResult. Supports both a success value
// and an error path so PostgrestException propagation can be tested too.
class _FakeRpcResult extends Fake implements PostgrestFilterBuilder<dynamic> {
  final dynamic _data;
  final Object? _error;
  _FakeRpcResult(this._data) : _error = null;
  _FakeRpcResult.error(this._error) : _data = null;

  @override
  Future<U> then<U>(
    FutureOr<U> Function(dynamic value) onValue, {
    Function? onError,
  }) {
    if (_error != null) {
      return Future<dynamic>.error(_error).then(onValue, onError: onError);
    }
    return Future<dynamic>.value(_data).then(onValue, onError: onError);
  }
}

void main() {
  test('markPaid inserts a pending_confirmation settlement from the current user', () async {
    final client = MockSupabaseClient();
    final auth = MockGoTrueClient();
    final table = MockQueryBuilder();

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
    when(() => client.from('settlements')).thenAnswer((_) => table);
    when(() => table.insert(any())).thenAnswer((_) => _FakeInsertResult({
          'id': 's1',
          'group_id': null,
          'from_user': 'u1',
          'to_user': 'u2',
          'amount': '500.00',
          'status': 'pending_confirmation',
          'created_at': '2026-07-27T10:00:00Z',
          'confirmed_at': null,
        }));

    final repo = SettlementRepository(client);
    final settlement =
        await repo.markPaid(toUser: 'u2', amountMinorUnits: 50000);

    expect(settlement.id, 's1');
    final captured = verify(() => table.insert(captureAny())).captured.single
        as Map<String, dynamic>;
    expect(captured['from_user'], 'u1');
    expect(captured['to_user'], 'u2');
    expect(captured['amount'], '500.00');
  });

  test('confirmSettlement calls the RPC and succeeds on a returned row', () async {
    final client = MockSupabaseClient();

    when(
      () => client.rpc(
        'confirm_settlement_and_award_coins',
        params: {'p_settlement_id': 's1'},
      ),
    ).thenAnswer(
      (_) => _FakeRpcResult({'id': 's1', 'status': 'confirmed'}),
    );

    final repo = SettlementRepository(client);
    await repo.confirmSettlement('s1');
    // No exception thrown means success.
    verify(
      () => client.rpc(
        'confirm_settlement_and_award_coins',
        params: {'p_settlement_id': 's1'},
      ),
    ).called(1);
  });

  test('confirmSettlement propagates PostgrestException when not authorized', () async {
    // Regression test: an unauthorized confirm (e.g. the payer trying to
    // self-confirm) now surfaces as a PostgrestException raised by the RPC
    // (`not_authorized`), and confirmSettlement must let it propagate
    // unchanged rather than swallowing or transforming it.
    final client = MockSupabaseClient();

    when(
      () => client.rpc(
        'confirm_settlement_and_award_coins',
        params: {'p_settlement_id': 's1'},
      ),
    ).thenAnswer(
      (_) => _FakeRpcResult.error(
        PostgrestException(message: 'not_authorized'),
      ),
    );

    final repo = SettlementRepository(client);
    expect(
      () => repo.confirmSettlement('s1'),
      throwsA(isA<PostgrestException>()),
    );
  });
}
