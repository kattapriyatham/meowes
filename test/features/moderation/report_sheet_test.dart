import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart' show friendRepositoryProvider;
import 'package:meowes_app/features/moderation/report_sheet.dart';
import 'package:meowes_app/repositories/friend_repository.dart';

class MockFriendRepository extends Mock implements FriendRepository {}

void main() {
  Future<void> open(WidgetTester tester, MockFriendRepository repo) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [friendRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: Consumer(
                builder: (context, ref, _) => ElevatedButton(
                  onPressed: () => showReportSheet(context, ref,
                      targetType: 'expense', targetId: 'e1'),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('submit is inert until a reason is picked, then files the report',
      (tester) async {
    final repo = MockFriendRepository();
    when(() => repo.reportContent(
          targetType: any(named: 'targetType'),
          targetId: any(named: 'targetId'),
          reason: any(named: 'reason'),
          details: any(named: 'details'),
        )).thenAnswer((_) async {});

    await open(tester, repo);

    await tester.tap(find.widgetWithText(PillButton, 'Submit report'), warnIfMissed: false);
    await tester.pump();
    verifyNever(() => repo.reportContent(
          targetType: any(named: 'targetType'),
          targetId: any(named: 'targetId'),
          reason: any(named: 'reason'),
          details: any(named: 'details'),
        ));

    await tester.tap(find.text('Spam'));
    await tester.pump();
    await tester.tap(find.widgetWithText(PillButton, 'Submit report'));
    await tester.pumpAndSettle();

    verify(() => repo.reportContent(
          targetType: 'expense',
          targetId: 'e1',
          reason: 'spam',
          details: any(named: 'details'),
        )).called(1);
    // Sheet closed on success.
    expect(find.text('Submit report'), findsNothing);
  });
}
