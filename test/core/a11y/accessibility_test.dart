import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowes_app/core/a11y/accessibility.dart';

void main() {
  testWidgets('glassDisabled true when user override set', (tester) async {
    late bool disabled;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        disabled = glassDisabled(context, userReduceTransparency: true);
        return const SizedBox();
      }),
    ));
    expect(disabled, isTrue);
  });

  testWidgets('motionReduced reflects MediaQuery', (tester) async {
    late bool reduced;
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(builder: (context) {
          reduced = motionReduced(context);
          return const SizedBox();
        }),
      ),
    ));
    expect(reduced, isTrue);
  });
}
