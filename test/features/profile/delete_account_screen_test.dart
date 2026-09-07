import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/auth/sign_in_screen.dart';
import 'package:meowes_app/features/profile/delete_account_screen.dart';
import 'package:meowes_app/repositories/auth_repository.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

final _btn = find.widgetWithText(PillButton, 'Delete my account');

Future<void> _pump(WidgetTester tester, MockAuthRepository repo) async {
  // Tall viewport so the whole screen fits without scrolling the ListView
  // (a partly-clipped button can't be reliably tapped).
  tester.view.physicalSize = const Size(1000, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(theme: AppTheme.dark, home: const DeleteAccountScreen()),
  ));
  await tester.pump();
}

void main() {
  testWidgets('the delete button is inert until the user types DELETE', (tester) async {
    final repo = MockAuthRepository();
    when(() => repo.deleteAccount()).thenAnswer((_) async {});
    await _pump(tester, repo);

    await tester.tap(_btn, warnIfMissed: false);
    await tester.pump();
    verifyNever(() => repo.deleteAccount());

    await tester.enterText(find.byType(TextField), 'delete'); // case-insensitive
    await tester.pump();
    await tester.tap(_btn);
    await tester.pumpAndSettle();

    verify(() => repo.deleteAccount()).called(1);
  });

  testWidgets('a successful delete lands on the sign-in screen', (tester) async {
    final repo = MockAuthRepository();
    when(() => repo.deleteAccount()).thenAnswer((_) async {});
    await _pump(tester, repo);

    await tester.enterText(find.byType(TextField), 'DELETE');
    await tester.pump();
    await tester.tap(_btn);
    await tester.pumpAndSettle();

    expect(find.byType(DeleteAccountScreen), findsNothing);
    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('a failed delete keeps the screen and shows a retry', (tester) async {
    final repo = MockAuthRepository();
    when(() => repo.deleteAccount()).thenThrow(Exception('boom'));
    await _pump(tester, repo);

    await tester.enterText(find.byType(TextField), 'DELETE');
    await tester.pump();
    await tester.tap(_btn);
    await tester.pumpAndSettle();

    expect(find.byType(DeleteAccountScreen), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
