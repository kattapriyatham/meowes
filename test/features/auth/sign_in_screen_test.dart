import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/features/auth/sign_in_screen.dart';
import 'package:meowes_app/repositories/auth_repository.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

Future<void> _pump(WidgetTester tester, TargetPlatform platform) async {
  debugDefaultTargetPlatformOverride = platform;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(MockAuthRepository()),
    ],
    child: MaterialApp(theme: AppTheme.dark, home: const SignInScreen()),
  ));
  await tester.pump();
}

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('iOS shows both Google and Apple sign-in (Guideline 4.8)', (tester) async {
    await _pump(tester, TargetPlatform.iOS);

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android shows only Google sign-in', (tester) async {
    await _pump(tester, TargetPlatform.android);

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });
}
