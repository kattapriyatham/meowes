import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/features/pet/feed_flow_screen.dart';
import 'package:meowes_app/models/pet.dart';

Pet _pet({
  DateTime? lastFishFedAt,
  DateTime? lastTreatsFedAt,
  DateTime? lastDryFoodFedAt,
}) =>
    Pet(
      userId: 'u1',
      name: 'Whiskers',
      coins: 10,
      moodScore: 60,
      lastCareAt: DateTime.now(),
      feedStreakDays: 1,
      lastFishFedAt: lastFishFedAt,
      lastTreatsFedAt: lastTreatsFedAt,
      lastDryFoodFedAt: lastDryFoodFedAt,
    );

Future<void> _pump(WidgetTester tester, Pet pet) async {
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(theme: AppTheme.light, home: FeedFlowScreen(pet: pet)),
  ));
  await tester.pump();
}

void main() {
  testWidgets('never-fed pet shows coin-reward badges and no timers', (tester) async {
    await _pump(tester, _pet());

    expect(find.text('Drag food to your cat'), findsOneWidget);
    expect(find.text('+3'), findsOneWidget);
    expect(find.text('+2'), findsNWidgets(2));
    expect(find.byIcon(Icons.timer_outlined), findsNothing);
  });

  testWidgets('feeding one food only cools that food down, others stay available', (tester) async {
    // Dry Food satiates for 4h; fed 1h ago leaves 3h remaining. Fish and
    // treats were never fed, so they must stay on their own coin-reward
    // badges — this is the whole point of independent per-food cooldowns.
    await _pump(
      tester,
      _pet(lastDryFoodFedAt: DateTime.now().subtract(const Duration(hours: 1))),
    );

    expect(find.text('Drag food to your cat'), findsOneWidget); // others still available
    expect(find.text('+3'), findsOneWidget); // fish untouched
    expect(find.text('+2'), findsOneWidget); // treats untouched, only dry food locked
    expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
  });

  testWidgets('all three on cooldown shows the all-full state', (tester) async {
    final now = DateTime.now();
    await _pump(
      tester,
      _pet(
        lastFishFedAt: now.subtract(const Duration(hours: 1)),
        lastTreatsFedAt: now.subtract(const Duration(hours: 1)),
        lastDryFoodFedAt: now.subtract(const Duration(hours: 1)),
      ),
    );

    expect(find.text('All full for now'), findsOneWidget);
    expect(find.text('+3'), findsNothing);
    expect(find.text('+2'), findsNothing);
    expect(find.byIcon(Icons.timer_outlined), findsNWidgets(3));
  });

  testWidgets('fish (6h satiation) still cools down 3h after eating', (tester) async {
    await _pump(
      tester,
      _pet(lastFishFedAt: DateTime.now().subtract(const Duration(hours: 3))),
    );
    expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
    expect(find.text('+3'), findsNothing); // fish specifically still locked
  });

  testWidgets('treats (2h satiation) is free again 3h after eating', (tester) async {
    await _pump(
      tester,
      _pet(lastTreatsFedAt: DateTime.now().subtract(const Duration(hours: 3))),
    );
    expect(find.text('Drag food to your cat'), findsOneWidget);
    expect(find.byIcon(Icons.timer_outlined), findsNothing);
  });
}
