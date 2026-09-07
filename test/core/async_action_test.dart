import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/async_action.dart';
import 'package:meowes_app/core/supabase_client.dart';

/// Pumps a button wired to [runAction] and exposes the enclosing container.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required Future<void> Function() action,
  String? successMessage,
}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => Consumer(
              builder: (context, ref, _) => ElevatedButton(
                onPressed: () => runAction(
                  context,
                  ref,
                  action: action,
                  successMessage: successMessage,
                ),
                child: const Text('run'),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  return container;
}

void main() {
  testWidgets('success bumps the data-changed ticker and shows the success SnackBar',
      (tester) async {
    final container = await _pump(
      tester,
      action: () async {},
      successMessage: 'Done!',
    );
    final before = container.read(dataChangedTickerProvider);

    await tester.tap(find.text('run'));
    await tester.pumpAndSettle();

    expect(container.read(dataChangedTickerProvider), before + 1);
    expect(find.text('Done!'), findsOneWidget);
  });

  testWidgets('failure shows the error message with a working Retry action',
      (tester) async {
    var attempts = 0;
    await _pump(tester, action: () async {
      attempts++;
      if (attempts == 1) {
        throw const PostgrestException(message: 'nope');
      }
    });

    await tester.tap(find.text('run'));
    await tester.pumpAndSettle();

    expect(find.text('nope'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('nope'), findsNothing); // second attempt succeeded
  });

  testWidgets('non-Postgrest errors fall back to a generic message', (tester) async {
    await _pump(tester, action: () async => throw Exception('raw'));

    await tester.tap(find.text('run'));
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
  });
}
