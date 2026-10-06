import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart';
import 'package:meowes_app/features/friends/friends_screen.dart';
import 'package:meowes_app/models/app_user.dart';
import 'package:meowes_app/models/friendship.dart';
import 'package:meowes_app/repositories/friend_repository.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockFriendRepository extends Mock implements FriendRepository {}

class _FakeRpcResult extends Fake implements PostgrestFilterBuilder<dynamic> {
  _FakeRpcResult(this.value);

  final dynamic value;

  @override
  Future<U> then<U>(
    FutureOr<U> Function(dynamic) onValue, {
    Function? onError,
  }) {
    return Future.value(value).then(onValue, onError: onError);
  }
}

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

    when(
      () => mockFriendRepo.watchFriendships(),
    ).thenAnswer((_) => Stream.value([]));

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

  testWidgets('FriendsScreen presents a hero above a draggable friends sheet', (
    tester,
  ) async {
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
    when(
      () => mockFriendRepo.watchFriendships(),
    ).thenAnswer((_) => Stream.value([]));

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

    expect(find.byKey(const Key('friends-hero-image')), findsOneWidget);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(find.byKey(const Key('friends-scroll-sheet')), findsOneWidget);
    expect(find.byKey(const Key('friends-search-field')), findsOneWidget);
  });

  testWidgets(
    'FriendsScreen filters cached friends without reloading balances',
    (tester) async {
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
        (_) => Stream.value([
          Friendship(
            userIdA: 'test-user-id',
            userIdB: 'friend-1',
            status: FriendshipStatus.accepted,
            requestedBy: 'test-user-id',
          ),
        ]),
      );
      when(
        () => mockFriendRepo.getPublicProfiles(['friend-1']),
      ).thenAnswer((_) async => [AppUser(id: 'friend-1', name: 'Susmitha')]);
      when(
        () => mockClient.rpc(
          'get_friend_balance',
          params: {'user_a': 'test-user-id', 'user_b': 'friend-1'},
        ),
      ).thenAnswer((_) => _FakeRpcResult(2903.50));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            supabaseClientProvider.overrideWithValue(mockClient),
            friendRepositoryProvider.overrideWithValue(mockFriendRepo),
          ],
          child: MaterialApp(theme: AppTheme.dark, home: const FriendsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('friends-search-field')),
        'sus',
      );
      await tester.pumpAndSettle();

      expect(find.text('Susmitha'), findsOneWidget);
      verify(() => mockFriendRepo.getPublicProfiles(['friend-1'])).called(1);
      verify(
        () => mockClient.rpc(
          'get_friend_balance',
          params: {'user_a': 'test-user-id', 'user_b': 'friend-1'},
        ),
      ).called(1);

      ProviderScope.containerOf(
        tester.element(find.byType(FriendsScreen)),
      ).read(dataChangedTickerProvider.notifier).state++;
      await tester.pumpAndSettle();

      verify(() => mockFriendRepo.getPublicProfiles(['friend-1'])).called(1);
      verify(
        () => mockClient.rpc(
          'get_friend_balance',
          params: {'user_a': 'test-user-id', 'user_b': 'friend-1'},
        ),
      ).called(1);
    },
  );

  testWidgets(
    'FriendsScreen uses dark hero copy against the light illustration',
    (tester) async {
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
      when(
        () => mockFriendRepo.watchFriendships(),
      ).thenAnswer((_) => Stream.value([]));

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

      final title = tester.widget<Text>(find.text('Friends').first);
      expect(title.style?.color, AppColors.textDark);
    },
  );
}
