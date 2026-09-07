import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/widgets/async_icon_button.dart';

Widget _host(Widget child) =>
    MaterialApp(theme: AppTheme.dark, home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('swaps the icon for a spinner while running and ignores repeat taps',
      (tester) async {
    final completer = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(_host(AsyncIconButton(
      icon: Icons.check,
      onPressed: () {
        calls++;
        return completer.future;
      },
    )));

    await tester.tap(find.byIcon(Icons.check));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);

    await tester.tap(find.byType(AsyncIconButton), warnIfMissed: false);
    await tester.pump();
    expect(calls, 1);

    completer.complete();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a sync onPressed just fires with no spinner', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(AsyncIconButton(icon: Icons.close, onPressed: () => taps++)));
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(taps, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('recovers after the future throws', (tester) async {
    final completer = Completer<void>();
    await tester.pumpWidget(_host(AsyncIconButton(
      icon: Icons.check,
      onPressed: () => completer.future,
    )));
    await tester.tap(find.byIcon(Icons.check));
    await tester.pump();
    completer.completeError(StateError('x'));
    await tester.pump();
    await tester.idle();
    await tester.pump();
    expect(tester.takeException(), isStateError);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });
}
