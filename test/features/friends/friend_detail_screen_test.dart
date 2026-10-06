import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart';
import 'package:meowes_app/features/friends/friend_detail_screen.dart';
import 'package:meowes_app/models/friend_activity_item.dart';
import 'package:meowes_app/repositories/expense_repository.dart';
import 'package:meowes_app/repositories/friend_repository.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockExpenseRepository extends Mock implements ExpenseRepository {}

class MockFriendRepository extends Mock implements FriendRepository {}

// SupabaseClient.rpc returns a PostgrestFilterBuilder (a Future-like
// builder), not a plain Future, so it needs a Fake with a real then().
class _FakeRpcResult extends Fake implements PostgrestFilterBuilder<dynamic> {
  final dynamic value;
  _FakeRpcResult(this.value);

  @override
  Future<U> then<U>(
    FutureOr<U> Function(dynamic) onValue, {
    Function? onError,
  }) {
    return Future.value(value).then(onValue, onError: onError);
  }
}

void main() {
  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());

  testWidgets('settled (net==0) rows are hidden until Show settled is tapped', (
    tester,
  ) async {
    final mockClient = MockSupabaseClient();
    final mockAuth = MockGoTrueClient();
    final mockExpenseRepo = MockExpenseRepository();
    final mockFriendRepo = MockFriendRepository();

    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(
      User(
        id: 'me',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-07-27T00:00:00Z',
      ),
    );
    when(
      () => mockClient.rpc(
        'get_friend_balance',
        params: {'user_a': 'me', 'user_b': 'friend-1'},
      ),
    ).thenAnswer((_) => _FakeRpcResult(-100.0));
    when(
      () => mockFriendRepo.getPublicProfiles(['friend-1']),
    ).thenAnswer((_) async => []);
    when(() => mockExpenseRepo.getFriendActivity('friend-1')).thenAnswer(
      (_) async => [
        FriendActivityItem(
          kind: FriendActivityKind.group,
          refId: 'g1',
          name: 'Goa Trip',
          net: -100.0,
          date: DateTime(2026, 7, 20),
        ),
        FriendActivityItem(
          kind: FriendActivityKind.expense,
          refId: 'e1',
          name: 'Dinner',
          net: 50.0,
          date: DateTime(2020, 7, 20),
          addedAt: DateTime(2020, 7, 20, 14, 30),
          paidByMe: true,
        ),
        FriendActivityItem(
          kind: FriendActivityKind.group,
          refId: 'g2',
          name: 'Flatmates',
          net: 0.0,
          date: DateTime(2026, 7, 10),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(mockClient),
          expenseRepositoryProvider.overrideWithValue(mockExpenseRepo),
          friendRepositoryProvider.overrideWithValue(mockFriendRepo),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const FriendDetailScreen(friendUserId: 'friend-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('friend-detail-hero-image')), findsOneWidget);
    expect(find.byKey(const Key('friend-detail-scroll-sheet')), findsOneWidget);
    expect(find.byKey(const Key('detail-sheet-toolbar')), findsOneWidget);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(find.text('Goa Trip'), findsOneWidget);
    expect(find.text('Flatmates'), findsNothing); // net 0 hidden
    expect(
      find.text('Paid by you · Added 20 Jul 2020, 2:30 PM'),
      findsOneWidget,
    );

    await tester.drag(find.byType(Scrollable), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show settled'));
    await tester.pumpAndSettle();

    expect(find.text('Flatmates'), findsOneWidget); // now visible
  });
}
