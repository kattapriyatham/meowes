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

// select('invite_code').eq('id', me).single() — eq() must return a type
// that still has .single(), so this doubles as both the select() result and
// the eq() result (mirrors _FakeListResult's role in pet_repository_test).
class _FakeSelectSingleChain extends Fake
    implements PostgrestFilterBuilder<PostgrestList> {
  final PostgrestMap value;
  _FakeSelectSingleChain(this.value);

  @override
  PostgrestFilterBuilder<PostgrestList> eq(String column, Object value) => this;

  @override
  PostgrestTransformBuilder<PostgrestMap> single() => _FakeSingleRow(value);
}

class _FakeRpcResult extends Fake implements PostgrestFilterBuilder<dynamic> {
  final dynamic data;
  final Object? error;
  _FakeRpcResult(this.data) : error = null;
  _FakeRpcResult.error(this.error) : data = null;

  @override
  Future<T> then<T>(FutureOr<T> Function(dynamic) onValue, {Function? onError}) {
    if (error != null) return Future<dynamic>.error(error!).then(onValue, onError: onError);
    return Future<dynamic>.value(data).then(onValue, onError: onError);
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

  test('getMyInviteCode reads invite_code off the current user\'s own row', () async {
    final client = MockSupabaseClient();
    final auth = MockGoTrueClient();
    final table = MockQueryBuilder();

    when(() => client.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(
      User(id: 'me', appMetadata: const {}, userMetadata: const {},
          aud: 'authenticated', createdAt: '2026-07-27T00:00:00Z'),
    );
    when(() => client.from('users')).thenAnswer((_) => table);
    when(() => table.select('invite_code'))
        .thenAnswer((_) => _FakeSelectSingleChain({'invite_code': 'abc123'}));

    final repo = FriendRepository(client);
    expect(await repo.getMyInviteCode(), 'abc123');
  });

  test('joinByInviteCode calls the RPC and returns the new friend\'s profile', () async {
    final client = MockSupabaseClient();

    when(() => client.rpc('join_friendship_by_code', params: {'invite_code_param': 'abc123'}))
        .thenAnswer((_) => _FakeRpcResult([
              {'id': 'friend-1', 'name': 'Sam', 'avatar_url': null},
            ]));

    final repo = FriendRepository(client);
    final friend = await repo.joinByInviteCode('abc123');

    expect(friend.id, 'friend-1');
    expect(friend.name, 'Sam');
  });

  test('joinByInviteCode throws InvalidInviteCodeException on a bad code', () async {
    final client = MockSupabaseClient();

    when(() => client.rpc('join_friendship_by_code', params: {'invite_code_param': 'nope'}))
        .thenAnswer((_) => _FakeRpcResult.error(
              PostgrestException(message: 'invalid_invite_code'),
            ));

    final repo = FriendRepository(client);
    expect(() => repo.joinByInviteCode('nope'), throwsA(isA<InvalidInviteCodeException>()));
  });

  test('joinByInviteCode throws CannotFriendSelfException on your own code', () async {
    final client = MockSupabaseClient();

    when(() => client.rpc('join_friendship_by_code', params: {'invite_code_param': 'mine'}))
        .thenAnswer((_) => _FakeRpcResult.error(
              PostgrestException(message: 'cannot_friend_self'),
            ));

    final repo = FriendRepository(client);
    expect(() => repo.joinByInviteCode('mine'), throwsA(isA<CannotFriendSelfException>()));
  });

  test('removeFriend deletes the friendship row with ordered user ids', () async {
    final client = MockSupabaseClient();
    final auth = MockGoTrueClient();
    final table = MockQueryBuilder();
    final deleteChain = _FakeFilterChain();

    when(() => client.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(
      User(id: 'bbbbbbbb-0000-0000-0000-000000000000', appMetadata: const {},
          userMetadata: const {}, aud: 'authenticated', createdAt: '2026-07-27T00:00:00Z'),
    );
    when(() => client.from('friendships')).thenAnswer((_) => table);
    when(() => table.delete()).thenAnswer((_) => deleteChain);

    await FriendRepository(client).removeFriend('aaaaaaaa-0000-0000-0000-000000000000');

    expect(deleteChain.eqCalls[0].value, 'aaaaaaaa-0000-0000-0000-000000000000');
    expect(deleteChain.eqCalls[1].value, 'bbbbbbbb-0000-0000-0000-000000000000');
  });

  test('blockUser calls the block_user RPC with the target id', () async {
    final client = MockSupabaseClient();
    when(() => client.rpc('block_user', params: {'p_target': 'friend-1'}))
        .thenAnswer((_) => _FakeRpcResult(null));

    await FriendRepository(client).blockUser('friend-1');

    verify(() => client.rpc('block_user', params: {'p_target': 'friend-1'})).called(1);
  });

  test('reportContent inserts a row scoped to the reporter', () async {
    final client = MockSupabaseClient();
    final auth = MockGoTrueClient();
    final table = MockQueryBuilder();

    when(() => client.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(
      User(id: 'me', appMetadata: const {}, userMetadata: const {},
          aud: 'authenticated', createdAt: '2026-07-27T00:00:00Z'),
    );
    when(() => client.from('content_reports')).thenAnswer((_) => table);
    when(() => table.insert(any())).thenAnswer((_) => _FakeInsertResult());

    await FriendRepository(client).reportContent(
      targetType: 'expense',
      targetId: 'e1',
      reason: 'spam',
      details: '  ',
    );

    final row = verify(() => table.insert(captureAny())).captured.single
        as Map<String, dynamic>;
    expect(row['reporter_id'], 'me');
    expect(row['target_type'], 'expense');
    expect(row['target_id'], 'e1');
    expect(row['reason'], 'spam');
    expect(row.containsKey('details'), isFalse); // blank details dropped
  });
}
