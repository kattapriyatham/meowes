import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/a11y/accessibility.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/repositories/friend_repository.dart';
import 'package:meowes_app/features/profile/profile_screen.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockGoTrueClient extends Mock implements GoTrueClient {}
class MockFriendRepository extends Mock implements FriendRepository {}

void main() {
  testWidgets('reduce-transparency switch flips the provider', (tester) async {
    final client = MockSupabaseClient();
    final auth = MockGoTrueClient();
    final friendRepo = MockFriendRepository();
    when(() => client.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(User(
      id: 'test-user-id', appMetadata: const {}, userMetadata: const {},
      aud: 'authenticated', createdAt: '2026-07-27T00:00:00Z'));
    when(() => friendRepo.getMyProfile()).thenAnswer((_) async => null);

    final container = ProviderContainer(overrides: [
      supabaseClientProvider.overrideWithValue(client),
      friendRepositoryProvider.overrideWithValue(friendRepo),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.dark, home: const ProfileScreen()),
    ));
    await tester.pump();
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    expect(container.read(reduceTransparencyProvider), isTrue);
  });
}
