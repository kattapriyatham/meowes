import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/features/groups/create_group_screen.dart';
import 'package:meowes_app/features/groups/groups_screen.dart';
import 'package:meowes_app/repositories/group_repository.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockGoTrueClient extends Mock implements GoTrueClient {}
class MockGroupRepository extends Mock implements GroupRepository {}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('GroupsScreen shows the Groups title', (tester) async {
    final mockClient = MockSupabaseClient();
    final mockAuth = MockGoTrueClient();
    final mockGroupRepo = MockGroupRepository();

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

    when(() => mockGroupRepo.watchMyGroups()).thenAnswer(
      (_) => Stream.value([]),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(mockClient),
          groupRepositoryProvider.overrideWithValue(mockGroupRepo),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const GroupsScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Groups'), findsWidgets);
  });
}
