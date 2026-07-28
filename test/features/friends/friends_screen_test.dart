import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart';
import 'package:meowes_app/features/friends/friends_screen.dart';
import 'package:meowes_app/repositories/friend_repository.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockGoTrueClient extends Mock implements GoTrueClient {}
class MockFriendRepository extends Mock implements FriendRepository {}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('FriendsScreen shows the Friends title', (tester) async {
    final mockClient = MockSupabaseClient();
    final mockAuth = MockGoTrueClient();
    final mockFriendRepo = MockFriendRepository();

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

    when(() => mockFriendRepo.watchFriendships()).thenAnswer(
      (_) => Stream.value([]),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(mockClient),
          friendRepositoryProvider.overrideWithValue(mockFriendRepo),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const FriendsScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Friends'), findsWidgets);
  });
}
