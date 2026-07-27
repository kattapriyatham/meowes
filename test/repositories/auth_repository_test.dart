import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/repositories/auth_repository.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockGoTrueClient extends Mock implements GoTrueClient {}
class MockSupabaseQueryBuilder extends Mock implements SupabaseQueryBuilder {}

// PostgrestFilterBuilder implements Future, and mocktail's Mock cannot
// reliably stub then() (its onError named-argument shape doesn't match
// what Dart's await protocol actually passes). A hand-written Fake with a
// real then() implementation sidesteps that entirely — Fake's noSuchMethod
// covers every other interface member we never call.
class _FakeUpsertBuilder extends Fake
    implements PostgrestFilterBuilder<PostgrestMap> {
  @override
  Future<U> then<U>(FutureOr<U> Function(PostgrestMap) onValue,
      {Function? onError}) {
    return Future.value(<String, dynamic>{}).then(onValue, onError: onError);
  }
}

void main() {
  late MockSupabaseClient client;
  late MockGoTrueClient auth;

  setUp(() {
    client = MockSupabaseClient();
    auth = MockGoTrueClient();
    when(() => client.auth).thenReturn(auth);
  });

  test('upsertProfile calls upsert on the users table with given fields', () async {
    final table = MockSupabaseQueryBuilder();

    when(() => client.from('users')).thenAnswer((_) => table);
    when(() => auth.currentUser).thenReturn(
      User(
        id: 'u1',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-07-27T00:00:00Z',
      ),
    );
    when(() => table.upsert(any())).thenAnswer((_) => _FakeUpsertBuilder());

    final repo = AuthRepository(client);
    await repo.upsertProfile(name: 'Alex', phoneNumber: '+911234567890');

    final captured = verify(() => table.upsert(captureAny())).captured.single
        as Map<String, dynamic>;
    expect(captured['id'], 'u1');
    expect(captured['name'], 'Alex');
    expect(captured['phone_number'], '+911234567890');
    expect(captured.containsKey('avatar_url'), isFalse);
  });
}
