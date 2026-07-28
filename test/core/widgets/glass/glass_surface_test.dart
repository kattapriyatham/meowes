import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowes_app/core/a11y/accessibility.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/glass/glass_surface.dart';

Widget _host(Widget child, {List<Override> overrides = const []}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: ThemeData(extensions: const [GlassTokens.dark]),
        home: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('renders BackdropFilter when blur enabled', (tester) async {
    await tester.pumpWidget(_host(const GlassSurface(child: Text('x'))));
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('no BackdropFilter when disableBlur', (tester) async {
    await tester.pumpWidget(_host(const GlassSurface(disableBlur: true, child: Text('x'))));
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('no BackdropFilter when reduceTransparencyProvider is true', (tester) async {
    await tester.pumpWidget(_host(
      const GlassSurface(child: Text('x')),
      overrides: [reduceTransparencyProvider.overrideWith((ref) => true)],
    ));
    expect(find.byType(BackdropFilter), findsNothing);
  });
}
