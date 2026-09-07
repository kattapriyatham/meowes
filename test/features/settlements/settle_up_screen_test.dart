import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/features/settlements/settle_up_screen.dart';
import 'package:meowes_app/models/settlement.dart';
import 'package:meowes_app/repositories/settlement_repository.dart';

class MockSettlementRepository extends Mock implements SettlementRepository {}

Settlement _pending() => Settlement(
      id: 's1',
      groupId: null,
      fromUser: 'me',
      toUser: 'friend-1',
      amountMinorUnits: 2500,
      status: SettlementStatus.pendingConfirmation,
      createdAt: DateTime(2026, 8, 31),
    );

Future<ProviderContainer> _pump(
  WidgetTester tester,
  MockSettlementRepository repo,
) async {
  final container = ProviderContainer(overrides: [
    settlementRepositoryProvider.overrideWithValue(repo),
  ]);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.dark,
      home: Navigator(
        onGenerateRoute: (_) => MaterialPageRoute(
          builder: (_) => const _Host(),
        ),
      ),
    ),
  ));
  return container;
}

/// A host screen that pushes SettleUpScreen so we can observe the pop.
class _Host extends StatelessWidget {
  const _Host();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const SettleUpScreen(
                toUser: 'friend-1',
                amountMinorUnits: 2500,
                toUserName: 'Sam',
              ),
            )),
            child: const Text('open'),
          ),
        ),
      );
}

void main() {
  testWidgets('shows a spinner while the payment is in flight, then pops with a confirmation SnackBar',
      (tester) async {
    final repo = MockSettlementRepository();
    final completer = Completer<Settlement>();
    when(() => repo.markPaid(
          toUser: any(named: 'toUser'),
          amountMinorUnits: any(named: 'amountMinorUnits'),
          groupId: any(named: 'groupId'),
        )).thenAnswer((_) => completer.future);

    await _pump(tester, repo);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Mark as Paid'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.text('Mark as Paid'));
    await tester.pump();

    // In flight: spinner shown, button gone.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Mark as Paid'), findsNothing);

    completer.complete(_pending());
    await tester.pumpAndSettle();

    // Popped back to the host, and the SnackBar explains the pending state.
    expect(find.byType(SettleUpScreen), findsNothing);
    expect(find.textContaining('waiting for Sam to confirm'), findsOneWidget);
  });

  testWidgets('a failed payment keeps the screen and surfaces the error', (tester) async {
    final repo = MockSettlementRepository();
    when(() => repo.markPaid(
          toUser: any(named: 'toUser'),
          amountMinorUnits: any(named: 'amountMinorUnits'),
          groupId: any(named: 'groupId'),
        )).thenThrow(const PostgrestException(message: 'row-level security'));

    await _pump(tester, repo);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark as Paid'));
    await tester.pumpAndSettle();

    expect(find.byType(SettleUpScreen), findsOneWidget);
    expect(find.text('Mark as Paid'), findsOneWidget); // re-enabled
    expect(find.text('row-level security'), findsOneWidget);
  });

  testWidgets('double-tap only records one payment', (tester) async {
    final repo = MockSettlementRepository();
    final completer = Completer<Settlement>();
    when(() => repo.markPaid(
          toUser: any(named: 'toUser'),
          amountMinorUnits: any(named: 'amountMinorUnits'),
          groupId: any(named: 'groupId'),
        )).thenAnswer((_) => completer.future);

    await _pump(tester, repo);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark as Paid'));
    await tester.pump();
    // Second tap lands on the spinner area; nothing to tap, but guard anyway.
    await tester.tap(find.byType(CircularProgressIndicator), warnIfMissed: false);
    await tester.pump();

    completer.complete(_pending());
    await tester.pumpAndSettle();

    verify(() => repo.markPaid(
          toUser: any(named: 'toUser'),
          amountMinorUnits: any(named: 'amountMinorUnits'),
          groupId: any(named: 'groupId'),
        )).called(1);
  });
}
