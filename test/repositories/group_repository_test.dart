import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/repositories/group_repository.dart';

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

void main() {
  test('createGroup inserts a group and adds the creator as a member', () async {
    final client = MockSupabaseClient();
    final auth = MockGoTrueClient();
    final groupsTable = MockQueryBuilder();
    final membersTable = MockQueryBuilder();

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
    when(() => client.from('groups')).thenAnswer((_) => groupsTable);
    when(() => client.from('group_members')).thenAnswer((_) => membersTable);
    when(() => groupsTable.insert(any())).thenAnswer((_) => _FakeInsertResult({
          'id': 'g1',
          'name': 'Trip',
          'created_by': 'u1',
          'invite_code': 'abc123',
        }));
    when(() => membersTable.insert(any())).thenAnswer((_) => _FakeInsertResult());

    final repo = GroupRepository(client);
    final group = await repo.createGroup('Trip');

    expect(group.id, 'g1');
    expect(group.inviteCode, 'abc123');
    final captured = verify(() => membersTable.insert(captureAny())).captured.single
        as Map<String, dynamic>;
    expect(captured['group_id'], 'g1');
    expect(captured['user_id'], 'u1');
  });
}
