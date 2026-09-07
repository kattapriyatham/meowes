import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart';
import 'package:meowes_app/features/friends/join_by_invite_screen.dart';
import 'package:meowes_app/models/app_user.dart';
import 'package:meowes_app/repositories/friend_repository.dart';

class MockFriendRepository extends Mock implements FriendRepository {}

Future<void> _pump(WidgetTester tester, MockFriendRepository repo) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [friendRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const JoinByInviteScreen(inviteCode: 'abc123'),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('shows the new friend\'s name on a successful join', (tester) async {
    final repo = MockFriendRepository();
    when(() => repo.joinByInviteCode('abc123'))
        .thenAnswer((_) async => AppUser(id: 'f1', name: 'Sam'));

    await _pump(tester, repo);

    expect(find.text("You're now friends with Sam!"), findsOneWidget);
  });

  testWidgets('shows an error for an invalid code', (tester) async {
    final repo = MockFriendRepository();
    when(() => repo.joinByInviteCode('abc123')).thenThrow(InvalidInviteCodeException());

    await _pump(tester, repo);

    expect(find.text('This invite link is no longer valid.'), findsOneWidget);
  });

  testWidgets('shows a friendly message for your own invite link', (tester) async {
    final repo = MockFriendRepository();
    when(() => repo.joinByInviteCode('abc123')).thenThrow(CannotFriendSelfException());

    await _pump(tester, repo);

    expect(find.text("That's your own invite link."), findsOneWidget);
  });
}
