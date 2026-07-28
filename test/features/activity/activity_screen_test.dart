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
import 'package:meowes_app/models/friendship.dart';
import 'package:meowes_app/models/settlement.dart';
import 'package:meowes_app/repositories/friend_repository.dart';
import 'package:meowes_app/repositories/settlement_repository.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockGoTrueClient extends Mock implements GoTrueClient {}
class MockFriendRepository extends Mock implements FriendRepository {}
class MockSettlementRepository extends Mock implements SettlementRepository {}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('ActivityScreen shows the Activity title', (tester) async {
    final mockClient = MockSupabaseClient();
    final mockAuth = MockGoTrueClient();
    final mockFriendRepo = MockFriendRepository();
    final mockSettlementRepo = MockSettlementRepository();

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
      (_) => Stream<List<Friendship>>.value(const []),
    );
    when(() => mockSettlementRepo.watchPendingForMe()).thenAnswer(
      (_) => Stream<List<Settlement>>.value(const []),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(mockClient),
          friendRepositoryProvider.overrideWithValue(mockFriendRepo),
          settlementRepositoryProvider.overrideWithValue(mockSettlementRepo),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const ActivityScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Activity'), findsWidgets);
  });
}
