import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/features/activity/activity_screen.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart';
import 'package:meowes_app/features/settlements/settle_up_screen.dart';
import 'package:meowes_app/models/activity_item.dart';
import 'package:meowes_app/models/friendship.dart';
import 'package:meowes_app/models/pet.dart';
import 'package:meowes_app/models/settlement.dart';
import 'package:meowes_app/repositories/activity_repository.dart';
import 'package:meowes_app/repositories/friend_repository.dart';
import 'package:meowes_app/repositories/pet_repository.dart';
import 'package:meowes_app/repositories/settlement_repository.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockGoTrueClient extends Mock implements GoTrueClient {}
class MockFriendRepository extends Mock implements FriendRepository {}
class MockSettlementRepository extends Mock implements SettlementRepository {}
class MockActivityRepository extends Mock implements ActivityRepository {}
class MockPetRepository extends Mock implements PetRepository {}

Pet _pet({DateTime? lastCheckinAt}) => Pet(
      userId: 'test-user-id',
      name: 'Whiskers',
      coins: 5,
      moodScore: 60,
      lastCareAt: DateTime.now(),
      lastCheckinAt: lastCheckinAt,
      feedStreakDays: 0,
    );

Future<void> _pump(
  WidgetTester tester, {
  List<Friendship> friendships = const [],
  List<Settlement> settlements = const [],
  List<ActivityItem> feed = const [],
  Pet? pet,
}) async {
  final client = MockSupabaseClient();
  final auth = MockGoTrueClient();
  final friendRepo = MockFriendRepository();
  final settlementRepo = MockSettlementRepository();
  final activityRepo = MockActivityRepository();
  final petRepo = MockPetRepository();

  when(() => client.auth).thenReturn(auth);
  when(() => auth.currentUser).thenReturn(User(
    id: 'test-user-id', appMetadata: const {}, userMetadata: const {},
    aud: 'authenticated', createdAt: '2026-07-27T00:00:00Z'));
  when(() => friendRepo.watchFriendships()).thenAnswer((_) => Stream.value(friendships));
  when(() => friendRepo.getPublicProfiles(any())).thenAnswer((_) async => []);
  when(() => settlementRepo.watchPendingForMe()).thenAnswer((_) => Stream.value(settlements));
  when(() => activityRepo.getMyActivityFeed()).thenAnswer((_) async => feed);
  when(() => petRepo.getOrCreatePet()).thenAnswer((_) async => pet ?? _pet());

  await tester.pumpWidget(ProviderScope(
    overrides: [
      supabaseClientProvider.overrideWithValue(client),
      friendRepositoryProvider.overrideWithValue(friendRepo),
      settlementRepositoryProvider.overrideWithValue(settlementRepo),
      activityRepositoryProvider.overrideWithValue(activityRepo),
      petRepositoryProvider.overrideWithValue(petRepo),
    ],
    child: MaterialApp(theme: AppTheme.dark, home: const ActivityScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the Activity title', (tester) async {
    await _pump(tester);
    expect(find.text('Activity'), findsWidgets);
  });

  testWidgets('nothing pending and no history shows the empty state', (tester) async {
    await _pump(tester);
    expect(find.text('No activity yet.'), findsOneWidget);
  });

  testWidgets('checked in today shows the Today card, not the empty state', (tester) async {
    await _pump(tester, pet: _pet(lastCheckinAt: DateTime.now()));
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('No activity yet.'), findsNothing);
  });

  testWidgets('history feed renders an expense, a settlement, and a pet activity', (tester) async {
    await _pump(tester, feed: [
      ActivityItem(
        kind: ActivityKind.expense,
        refId: 'e1',
        title: 'Dinner',
        counterpartId: 'friend-1',
        isMine: true,
        amount: 500,
        occurredAt: DateTime(2026, 8, 10),
      ),
      ActivityItem(
        kind: ActivityKind.settlement,
        refId: 's1',
        counterpartId: 'friend-1',
        isMine: false,
        amount: 200,
        occurredAt: DateTime(2026, 8, 9),
      ),
      ActivityItem(
        kind: ActivityKind.petActivity,
        refId: 'p1',
        title: 'Spa Day',
        amount: 80,
        occurredAt: DateTime(2026, 8, 8),
      ),
    ]);

    expect(find.text('History'), findsOneWidget);
    expect(find.text('Dinner'), findsOneWidget);
    expect(find.text('₹500.00'), findsOneWidget);
    expect(find.text('... paid you'), findsOneWidget); // profile lookup unresolved -> '...'
    expect(find.text('Spa Day'), findsOneWidget);
    expect(find.text('-80 coins'), findsOneWidget);
  });
}
