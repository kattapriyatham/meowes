import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart';
import 'package:meowes_app/features/groups/create_group_screen.dart';
import 'package:meowes_app/features/settlements/settle_up_screen.dart';
import 'package:meowes_app/models/app_user.dart';
import 'package:meowes_app/models/pet.dart';
import 'package:meowes_app/repositories/friend_repository.dart';
import 'package:meowes_app/repositories/group_repository.dart';
import 'package:meowes_app/repositories/pet_repository.dart';
import 'package:meowes_app/repositories/settlement_repository.dart';
import 'package:meowes_app/features/root/home_shell.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockGoTrueClient extends Mock implements GoTrueClient {}
class MockFriendRepository extends Mock implements FriendRepository {}
class MockGroupRepository extends Mock implements GroupRepository {}
class MockPetRepository extends Mock implements PetRepository {}
class MockSettlementRepository extends Mock implements SettlementRepository {}

void main() {
  testWidgets('shows dock and switches to the Profile tab', (tester) async {
    final client = MockSupabaseClient();
    final auth = MockGoTrueClient();
    final friendRepo = MockFriendRepository();
    final groupRepo = MockGroupRepository();
    final petRepo = MockPetRepository();
    final settlementRepo = MockSettlementRepository();
    when(() => client.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(User(
      id: 'test-user-id', appMetadata: const {}, userMetadata: const {},
      aud: 'authenticated', createdAt: '2026-07-27T00:00:00Z'));
    when(() => friendRepo.watchFriendships()).thenAnswer((_) => Stream.value([]));
    when(() => friendRepo.getMyProfile()).thenAnswer((_) async => null);
    when(() => friendRepo.getPublicProfiles(any())).thenAnswer((_) async => <AppUser>[]);
    when(() => groupRepo.watchMyGroups()).thenAnswer((_) => Stream.value([]));
    when(() => petRepo.getOrCreatePet()).thenAnswer(
      (_) async => Pet(
        userId: 'test-user-id',
        coins: 0,
        moodScore: 50,
        lastCareAt: DateTime.parse('2026-07-27T00:00:00Z'),
        feedStreakDays: 0,
      ),
    );
    when(() => petRepo.dailyCheckIn()).thenThrow(AlreadyCheckedInException());
    when(() => settlementRepo.watchPendingForMe()).thenAnswer((_) => Stream.value([]));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        supabaseClientProvider.overrideWithValue(client),
        friendRepositoryProvider.overrideWithValue(friendRepo),
        groupRepositoryProvider.overrideWithValue(groupRepo),
        petRepositoryProvider.overrideWithValue(petRepo),
        settlementRepositoryProvider.overrideWithValue(settlementRepo),
      ],
      child: MaterialApp(theme: AppTheme.dark, home: const HomeShell()),
    ));
    await tester.pump();
    await tester.tap(find.byTooltip('Profile'));
    await tester.pump();
    expect(find.byType(HomeShell), findsOneWidget);
  });
}
