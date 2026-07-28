import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/widgets/glass/glass_button.dart';

void main() {
  testWidgets('GlassButton fires onPressed and shows label', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: GlassButton(label: 'Add expense', onPressed: () => tapped = true)),
    ));
    expect(find.text('Add expense'), findsOneWidget);
    await tester.tap(find.text('Add expense'));
    expect(tapped, isTrue);
  });
}
