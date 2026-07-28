// test/repositories/friend_repository_test.dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/repositories/friend_repository.dart';

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
  final List<MapEntry<String, dynamic>> eqCalls = [];

  @override
  PostgrestFilterBuilder<PostgrestList> eq(String column, Object value) {
    eqCalls.add(MapEntry(column, value));
    return this;
  }

  @override
  Future<U> then<U>(FutureOr<U> Function(PostgrestList) onValue, {Function? onError}) {
    return Future.value(<Map<String, dynamic>>[]).then(onValue, onError: onError);
  }
}

void main() {
  test('sendFriendRequest inserts a pending friendship with ordered user ids', () async {
    final client = MockSupabaseClient();
    final auth = MockGoTrueClient();
    final table = MockQueryBuilder();

    when(() => client.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(
      User(
        id: 'bbbbbbbb-0000-0000-0000-000000000000',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-07-27T00:00:00Z',
      ),
    );
    when(() => client.from('friendships')).thenAnswer((_) => table);
    when(() => table.insert(any())).thenAnswer((_) => _FakeInsertResult());

    final repo = FriendRepository(client);
    await repo.sendFriendRequest('aaaaaaaa-0000-0000-0000-000000000000');

    final captured = verify(() => table.insert(captureAny())).captured.single
        as Map<String, dynamic>;
    // user_id_a < user_id_b is enforced by the DB check constraint, so the
    // repository must order the pair itself before inserting.
    expect(captured['user_id_a'], 'aaaaaaaa-0000-0000-0000-000000000000');
    expect(captured['user_id_b'], 'bbbbbbbb-0000-0000-0000-000000000000');
    expect(captured['status'], 'pending');
    expect(captured['requested_by'], 'bbbbbbbb-0000-0000-0000-000000000000');
  });

  test('declineFriendRequest deletes the friendship row with ordered user ids', () async {
    final client = MockSupabaseClient();
    final auth = MockGoTrueClient();
    final table = MockQueryBuilder();
    final deleteChain = _FakeFilterChain();

    when(() => client.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(
      User(
        id: 'bbbbbbbb-0000-0000-0000-000000000000',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-07-27T00:00:00Z',
      ),
    );
    when(() => client.from('friendships')).thenAnswer((_) => table);
    when(() => table.delete()).thenAnswer((_) => deleteChain);

    final repo = FriendRepository(client);
    await repo.declineFriendRequest('aaaaaaaa-0000-0000-0000-000000000000');

    expect(deleteChain.eqCalls.length, 2);
    expect(deleteChain.eqCalls[0].key, 'user_id_a');
    expect(deleteChain.eqCalls[0].value, 'aaaaaaaa-0000-0000-0000-000000000000');
    expect(deleteChain.eqCalls[1].key, 'user_id_b');
    expect(deleteChain.eqCalls[1].value, 'bbbbbbbb-0000-0000-0000-000000000000');
  });
}
