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
import 'package:meowes_app/models/pet.dart';
import 'package:meowes_app/repositories/friend_repository.dart';
import 'package:meowes_app/repositories/group_repository.dart';
import 'package:meowes_app/repositories/pet_repository.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockGoTrueClient extends Mock implements GoTrueClient {}
class MockFriendRepository extends Mock implements FriendRepository {}
class MockGroupRepository extends Mock implements GroupRepository {}
class MockPetRepository extends Mock implements PetRepository {}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('HomeScreen is an overview: greeting + balance hero + actions, no Groups list', (tester) async {
    final mockClient = MockSupabaseClient();
    final mockAuth = MockGoTrueClient();
    final mockFriendRepo = MockFriendRepository();
    final mockGroupRepo = MockGroupRepository();
    final mockPetRepo = MockPetRepository();

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
    when(() => mockFriendRepo.getMyProfile()).thenAnswer((_) async => null);
    when(() => mockGroupRepo.watchMyGroups()).thenAnswer(
      (_) => Stream.value([]),
    );
    when(() => mockPetRepo.getOrCreatePet()).thenAnswer(
      (_) async => Pet(
        userId: 'test-user-id',
        coins: 0,
        moodScore: 50,
        lastCareAt: DateTime.parse('2026-07-27T00:00:00Z'),
        feedStreakDays: 0,
      ),
    );
    when(() => mockPetRepo.dailyCheckIn())
        .thenThrow(AlreadyCheckedInException());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(mockClient),
          friendRepositoryProvider.overrideWithValue(mockFriendRepo),
          groupRepositoryProvider.overrideWithValue(mockGroupRepo),
          petRepositoryProvider.overrideWithValue(mockPetRepo),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const HomeScreen()),
      ),
    );
    await tester.pump();

    // Groups (and Friends) lists have moved to their own tabs — Home is now
    // just an overview and must not render either section header/list.
    expect(find.text('Groups'), findsNothing);
    expect(find.text('Friends'), findsNothing);

    // Overview content: greeting, balance hero, primary actions.
    expect(find.text('Hi there'), findsOneWidget);
    expect(find.text('Add expense'), findsOneWidget);
  });
}
