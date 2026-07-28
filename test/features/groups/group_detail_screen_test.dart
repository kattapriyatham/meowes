import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart';
import 'package:meowes_app/features/groups/group_detail_screen.dart';
import 'package:meowes_app/models/expense.dart';
import 'package:meowes_app/repositories/expense_repository.dart';
import 'package:meowes_app/repositories/friend_repository.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockGoTrueClient extends Mock implements GoTrueClient {}
class MockExpenseRepository extends Mock implements ExpenseRepository {}
class MockFriendRepository extends Mock implements FriendRepository {}

// from('group_members').select('user_id').eq('group_id', ...) resolves to a
// list; model the builder chain with Fakes that carry a real then().
class _FakeQueryBuilder extends Fake implements SupabaseQueryBuilder {
  final List<Map<String, dynamic>> value;
  _FakeQueryBuilder(this.value);
  @override
  PostgrestFilterBuilder<PostgrestList> select([String columns = '*']) => _FakeSelect(value);
}

class _FakeSelect extends Fake implements PostgrestFilterBuilder<PostgrestList> {
  final List<Map<String, dynamic>> value;
  _FakeSelect(this.value);
  @override
  PostgrestFilterBuilder<PostgrestList> eq(String column, Object val) => this;
  @override
  Future<U> then<U>(FutureOr<U> Function(PostgrestList) onValue, {Function? onError}) {
    return Future.value(value).then(onValue, onError: onError);
  }
}

// rpc('get_group_debts', ...) returns a Future-like builder.
class _FakeRpcResult extends Fake implements PostgrestFilterBuilder<dynamic> {
  final dynamic value;
  _FakeRpcResult(this.value);
  @override
  Future<U> then<U>(FutureOr<U> Function(dynamic) onValue, {Function? onError}) {
    return Future.value(value).then(onValue, onError: onError);
  }
}

void main() {
  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());

  testWidgets('Group screen shows an add-expense FAB once members load', (tester) async {
    final mockClient = MockSupabaseClient();
    final mockAuth = MockGoTrueClient();
    final mockExpenseRepo = MockExpenseRepository();
    final mockFriendRepo = MockFriendRepository();

    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(User(
      id: 'me', appMetadata: const {}, userMetadata: const {},
      aud: 'authenticated', createdAt: '2026-07-27T00:00:00Z',
    ));
    when(() => mockClient.from('group_members'))
        .thenAnswer((_) => _FakeQueryBuilder([{'user_id': 'me'}, {'user_id': 'friend-1'}]));
    when(() => mockClient.rpc('get_group_debts', params: {'target_group_id': 'g1'}))
        .thenAnswer((_) => _FakeRpcResult(<dynamic>[]));
    when(() => mockFriendRepo.getPublicProfiles(any())).thenAnswer((_) async => []);
    when(() => mockExpenseRepo.watchExpenses(groupId: 'g1'))
        .thenAnswer((_) => Stream<List<Expense>>.value([]));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        supabaseClientProvider.overrideWithValue(mockClient),
        expenseRepositoryProvider.overrideWithValue(mockExpenseRepo),
        friendRepositoryProvider.overrideWithValue(mockFriendRepo),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const GroupDetailScreen(groupId: 'g1')),
    ));
    await tester.pumpAndSettle();

    final fab = find.byType(FloatingActionButton);
    expect(fab, findsOneWidget);
    expect(find.descendant(of: fab, matching: find.byIcon(Icons.add)), findsOneWidget);
    expect(tester.widget<FloatingActionButton>(fab).onPressed, isNotNull);
  });
}
