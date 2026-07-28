import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/widgets/glass/glass_scaffold.dart';
import 'package:meowes_app/core/widgets/glass/glass_app_bar.dart';

void main() {
  testWidgets('GlassScaffold shows body, app bar title, and dock', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: const GlassScaffold(
        appBar: GlassAppBar(title: 'Groups'),
        bottomDock: Text('dock'),
        body: Text('body'),
      ),
    ));
    expect(find.text('body'), findsOneWidget);
    expect(find.text('Groups'), findsOneWidget);
    expect(find.text('dock'), findsOneWidget);
  });
}
