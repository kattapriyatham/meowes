import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/widgets/glass/glass_nav_dock.dart';

void main() {
  testWidgets('renders 6 items and reports taps', (tester) async {
    var idx = -1;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: GlassNavDock(currentIndex: 0, onTap: (i) => idx = i)),
      ),
    ));
    expect(find.byType(Tooltip), findsNWidgets(6));
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Pet'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    await tester.tap(find.byTooltip('Groups'));
    expect(idx, 3);
  });
}
