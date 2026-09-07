import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/widgets/pill_button.dart';

Widget _host(Widget child) =>
    MaterialApp(theme: AppTheme.dark, home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('sync onTap fires and never shows a spinner', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(PillButton(label: 'Go', onTap: () => taps++)));

    await tester.tap(find.text('Go'));
    await tester.pump();

    expect(taps, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('async onTap shows a spinner and swallows taps until it resolves',
      (tester) async {
    final completer = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(_host(PillButton(
      label: 'Save',
      onTap: () {
        calls++;
        return completer.future;
      },
    )));

    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Save'), findsNothing);

    // Taps while in flight are ignored.
    await tester.tap(find.byType(PillButton));
    await tester.pump();
    expect(calls, 1);

    completer.complete();
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('a null onTap renders dimmed and inert', (tester) async {
    await tester.pumpWidget(_host(const PillButton(label: 'Nope', onTap: null)));

    final opacity = tester.widget<Opacity>(
      find.descendant(of: find.byType(PillButton), matching: find.byType(Opacity)),
    );
    expect(opacity.opacity, 0.5);
  });

  testWidgets('the spinner clears even if onTap throws', (tester) async {
    final completer = Completer<void>();
    await tester.pumpWidget(_host(PillButton(
      label: 'Boom',
      onTap: () => completer.future,
    )));

    await tester.tap(find.text('Boom'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.completeError(StateError('x'));
    await tester.pump();
    await tester.idle();
    await tester.pump();

    // Error is logged (not swallowed, not an uncaught async crash)...
    expect(tester.takeException(), isStateError);
    // ...and the button recovers: spinner gone, label back.
    expect(find.text('Boom'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
