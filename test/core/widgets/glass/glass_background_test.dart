import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/glass/glass_background.dart';

void main() {
  testWidgets('paints without BackdropFilter and shows child', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [GlassTokens.dark]),
      home: const GlassBackground(child: Text('hello', textDirection: TextDirection.ltr)),
    ));
    expect(find.text('hello'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
  });
}
