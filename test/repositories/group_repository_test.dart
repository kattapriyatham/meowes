import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/repositories/group_repository.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockGoTrueClient extends Mock implements GoTrueClient {}

// PostgrestFilterBuilder implements Future, and mocktail's Mock cannot
// reliably stub then() (its onError named-argument shape doesn't match
// what Dart's await protocol actually passes). A hand-written Fake with a
// real then() implementation sidesteps that — client.rpc(...) also returns
// a PostgrestFilterBuilder, and neither repository method here chains
// .select()/.single() off an rpc() call, so a bare Fake is enough.
class _FakeRpcResult extends Fake implements PostgrestFilterBuilder<dynamic> {
  final dynamic value;
  _FakeRpcResult(this.value);

  @override
  Future<U> then<U>(FutureOr<U> Function(dynamic) onValue,
      {Function? onError}) {
    return Future.value(value).then(onValue, onError: onError);
  }
}

void main() {
  test('createGroup calls the create_group RPC, not insert().select().single()', () async {
    // Regression test: groups RLS is member-only SELECT, and at insert
    // time the creator isn't a group_members row yet — a direct
    // insert().select().single() would get zero rows back. Creation must
    // go through the SECURITY DEFINER RPC instead.
    final client = MockSupabaseClient();
    final auth = MockGoTrueClient();

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
    when(() => client.rpc('create_group', params: any(named: 'params')))
        .thenAnswer((_) => _FakeRpcResult([
              {
                'id': 'g1',
                'name': 'Trip',
                'created_by': 'u1',
                'invite_code': 'abc123',
              }
            ]));

    final repo = GroupRepository(client);
    final group = await repo.createGroup('Trip');

    expect(group.id, 'g1');
    expect(group.inviteCode, 'abc123');
    verifyNever(() => client.from('groups'));
    verifyNever(() => client.from('group_members'));
    final captured = verify(() =>
            client.rpc('create_group', params: captureAny(named: 'params')))
        .captured
        .single as Map<String, dynamic>;
    expect(captured['p_name'], 'Trip');
  });

  test('joinByInviteCode calls the join_group_by_code RPC, not a direct table select', () async {
    // Regression test: groups RLS is member-only SELECT, so a non-member
    // can never see the row via a plain .from('groups').select() — joining
    // must go through the SECURITY DEFINER RPC instead.
    final client = MockSupabaseClient();
    final auth = MockGoTrueClient();

    when(() => client.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(
      User(
        id: 'u2',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-07-27T00:00:00Z',
      ),
    );
    when(() => client.rpc('join_group_by_code', params: any(named: 'params')))
        .thenAnswer((_) => _FakeRpcResult([
              {
                'id': 'g1',
                'name': 'Trip',
                'created_by': 'u1',
                'invite_code': 'abc123',
              }
            ]));

    final repo = GroupRepository(client);
    final group = await repo.joinByInviteCode('abc123');

    expect(group.id, 'g1');
    expect(group.inviteCode, 'abc123');
    verifyNever(() => client.from('groups'));
    final captured = verify(() =>
            client.rpc('join_group_by_code', params: captureAny(named: 'params')))
        .captured
        .single as Map<String, dynamic>;
    expect(captured['invite_code_param'], 'abc123');
  });

  test('joinByInviteCode throws a clear error for an invalid invite code', () async {
    final client = MockSupabaseClient();
    final auth = MockGoTrueClient();

    when(() => client.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(
      User(
        id: 'u2',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-07-27T00:00:00Z',
      ),
    );
    when(() => client.rpc('join_group_by_code', params: any(named: 'params')))
        .thenAnswer((_) => _FakeRpcResult(<dynamic>[]));

    final repo = GroupRepository(client);
    expect(() => repo.joinByInviteCode('badcode'), throwsStateError);
  });
}
