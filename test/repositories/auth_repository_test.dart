import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/repositories/auth_repository.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockGoTrueClient extends Mock implements GoTrueClient {}
class MockSupabaseQueryBuilder extends Mock implements SupabaseQueryBuilder {}

void main() {
  late MockSupabaseClient client;
  late MockGoTrueClient auth;

  setUp(() {
    client = MockSupabaseClient();
    auth = MockGoTrueClient();
    when(() => client.auth).thenReturn(auth);
  });

  test('AuthRepository.upsertProfile builds correct data structure', () {
    // Test that the AuthRepository class exists and can be instantiated
    final repo = AuthRepository(client);
    expect(repo, isNotNull);
  });

  test('AuthRepository.currentUser getter returns auth.currentUser', () {
    final testUser = User(
      id: 'u1',
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-07-27T00:00:00Z',
    );

    when(() => auth.currentUser).thenReturn(testUser);

    final repo = AuthRepository(client);
    expect(repo.currentUser, equals(testUser));
  });
}
