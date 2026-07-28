import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/features/home/home_screen.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart';
import 'package:meowes_app/features/groups/create_group_screen.dart';
import 'package:meowes_app/repositories/friend_repository.dart';
import 'package:meowes_app/repositories/group_repository.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockGoTrueClient extends Mock implements GoTrueClient {}
class MockRealtimeChannel extends Mock implements RealtimeChannel {}
class MockFriendRepository extends Mock implements FriendRepository {}
class MockGroupRepository extends Mock implements GroupRepository {}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('HomeScreen shows a greeting and balance hero overview', (tester) async {
    final mockClient = MockSupabaseClient();
    final mockAuth = MockGoTrueClient();
    final mockFriendRepo = MockFriendRepository();
    final mockGroupRepo = MockGroupRepository();

    // Mock the auth and user
    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(
      User(
        id: 'test-user-id',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-07-27T00:00:00Z',
      ),
    );

    // Mock the repositories to return empty streams
    when(() => mockFriendRepo.watchFriendships()).thenAnswer(
      (_) => Stream.value([]),
    );
    when(() => mockFriendRepo.getMyProfile()).thenAnswer((_) async => null);
    when(() => mockGroupRepo.watchMyGroups()).thenAnswer(
      (_) => Stream.value([]),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(mockClient),
          friendRepositoryProvider.overrideWithValue(mockFriendRepo),
          groupRepositoryProvider.overrideWithValue(mockGroupRepo),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const HomeScreen()),
      ),
    );
    await tester.pump();
    expect(find.text('Hi there'), findsOneWidget);
    expect(find.text('All settled up'), findsOneWidget);
    expect(find.text('Add expense'), findsOneWidget);
    expect(find.text('Settle up'), findsOneWidget);
  });
}
