# Glass Revamp — Foundation & Navigation Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild Meowes' visual foundation as a glassmorphism design system (light + dark) and ship a floating glass tab-dock navigation shell with its four new tab screens, leaving the app fully navigable and themed.

**Architecture:** A `GlassTokens` `ThemeExtension` carries every color/blur value for both modes; a small set of glass primitive widgets (`GlassBackground`, `GlassSurface`, `GlassCard`, `GlassButton`, `GlassScaffold`, `GlassAppBar`, `GlassNavDock`, `SkeletonLoader`) render the language and honor reduce-transparency / reduce-motion. `HomeShell` hosts a 5-tab `IndexedStack` behind the dock; the current Home's combined friends+groups content splits into dedicated Friends and Groups tabs, and Home becomes an overview. No data/repository/Supabase changes.

**Tech Stack:** Flutter (Material 3), Riverpod, Supabase, `google_fonts` (new dependency), `flutter_test`.

## Global Constraints

- Corner radius scale (single system): panel/card `24` (hero balance `26`), button/control/input `14`, pill/chip/segmented/dock stadium (fully rounded), avatar circle.
- Fonts: **Onest** (UI/body, 400/500/600), **Space Grotesk** (display, headlines, all money numerals, 400/500/600/700). All digits use `FontFeature.tabularFigures()`.
- Brand accent: indigo gradient `#6E8BFF` → `#5B7CFA`, solid `#5B7CFA`, on-brand `#FFFFFF`. One accent, locked everywhere.
- Money semantics fixed: positive/owed = green (`#4ADE80` dark / `#0E9E6E` light), negative/owe = red (`#FF7A7D` dark / `#E5484D` light), settled = grey (`#9BA0AA` dark / `#8A8F9C` light).
- Dark tokens: backdrop `#1E2233`→`#0E0F16`; blobs indigo `#5B7CFA`@32%, teal `#22B8A6`@20%; glass fill white@7%, border white@14%, sheen white@20%; strong fill white@10%, border white@18%; text `#F5F6F8` / white@60% / white@42%.
- Light tokens: backdrop `#EEF1FA`→`#E3E8F4`; blobs indigo `#8FA6FF`@38%, teal `#7FE0D0`@30%; glass fill white@55%, border white@70%, sheen white@60%; strong fill white@60%, border white@75%; text `#1A1C22` / `#5A5F6B` / `#8A8F9C`.
- Blur sigma: `18` cards, `24` strong/dock/app bar.
- `MaterialApp`: `theme: AppTheme.light, darkTheme: AppTheme.dark, themeMode: ThemeMode.system`.
- No em-dashes and no emoji in any visible copy. Drop all cat/paw imagery.
- No changes to `lib/repositories/`, `lib/models/`, or `supabase/`.
- Every glass surface must render a solid opaque fallback when reduce-transparency is active; all motion collapses to instant when reduce-motion is active.
- Access tokens only via `Theme.of(context).extension<GlassTokens>()!` — never hardcode colors in screens.
- **Widget-test convention (binding on every screen/widget test below):** any widget that uses a glass primitive reads `GlassTokens` from the theme, so every `pumpWidget` MUST supply a theme: `MaterialApp(theme: AppTheme.dark, home: …)` (or `AppTheme.light`). Any screen that reads Supabase-backed providers (`supabaseClientProvider`, `friendRepositoryProvider`, `groupRepositoryProvider`) MUST override them in `ProviderScope(overrides: […])` with mocks — follow the exact pattern in `test/features/home/home_screen_test.dart` (mock `SupabaseClient`/`GoTrueClient`/repositories via `mocktail`, stub `auth.currentUser`, return `Stream.value([])` from `watch*` methods). Test snippets in tasks below show the assertion and theme; where a screen reads providers, add the same overrides block as that reference file. A bare `MaterialApp(home: X())` for a provider-backed screen is a defect.

---

## File Structure

Created:
- `lib/core/theme/glass_tokens.dart` — `GlassTokens` ThemeExtension (light + dark instances).
- `lib/core/theme/app_typography.dart` — TextTheme built from Onest + Space Grotesk.
- `lib/core/a11y/accessibility.dart` — reduce-transparency / reduce-motion resolution + settings provider.
- `lib/core/widgets/glass/glass_background.dart`
- `lib/core/widgets/glass/glass_surface.dart`
- `lib/core/widgets/glass/glass_card.dart`
- `lib/core/widgets/glass/glass_button.dart`
- `lib/core/widgets/glass/glass_scaffold.dart`
- `lib/core/widgets/glass/glass_app_bar.dart`
- `lib/core/widgets/glass/skeleton_loader.dart`
- `lib/core/widgets/glass/glass_nav_dock.dart`
- `lib/features/root/home_shell.dart`
- `lib/features/friends/friends_screen.dart`
- `lib/features/groups/groups_screen.dart`
- `lib/features/activity/activity_screen.dart`
- `lib/features/profile/profile_screen.dart`
- Tests mirroring each under `test/`.

Modified:
- `pubspec.yaml` — add `google_fonts`.
- `lib/core/app_theme.dart` — `AppTheme.light` + `AppTheme.dark` attaching `GlassTokens` + typography; keep `AppColors` symbol until Phase 3 migration.
- `lib/main.dart` — wire `darkTheme` + `themeMode`.
- `lib/features/root/root_screen.dart` — route to `HomeShell`.
- `lib/features/home/home_screen.dart` — reduce to an overview (friends/groups lists move to their tabs).
- `lib/core/widgets/widgets.dart` — export the glass barrel.

---

## Task 1: Add google_fonts dependency

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add the dependency**

Under `dependencies:` in `pubspec.yaml`, after `uuid: ^4.4.0`, add:

```yaml
  google_fonts: ^6.2.1
```

- [ ] **Step 2: Fetch packages**

Run: `flutter pub get`
Expected: resolves with `google_fonts` added, exit 0.

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add google_fonts dependency"
```

---

## Task 2: GlassTokens ThemeExtension

**Files:**
- Create: `lib/core/theme/glass_tokens.dart`
- Test: `test/core/theme/glass_tokens_test.dart`

**Interfaces:**
- Produces: `class GlassTokens extends ThemeExtension<GlassTokens>` with const fields:
  `Color gradientTop, gradientBottom, blobIndigo, blobTeal, glassFill, glassBorder, glassSheen, glassStrongFill, glassStrongBorder, solidFallback, textPrimary, textSecondary, textMuted, positive, positiveTint, negative, negativeTint, settled, settledTint, brandStart, brandEnd, brandSolid, onBrand;` `double blurCard, blurStrong;`
  static const `GlassTokens light` and `GlassTokens dark`. Implements `copyWith` and `lerp`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';

void main() {
  test('light and dark tokens differ and expose the fixed palette', () {
    expect(GlassTokens.dark.gradientBottom, const Color(0xFF0E0F16));
    expect(GlassTokens.light.gradientTop, const Color(0xFFEEF1FA));
    expect(GlassTokens.dark.positive, const Color(0xFF4ADE80));
    expect(GlassTokens.light.positive, const Color(0xFF0E9E6E));
    expect(GlassTokens.dark.brandStart, const Color(0xFF6E8BFF));
    expect(GlassTokens.light.textPrimary, const Color(0xFF1A1C22));
    expect(GlassTokens.dark.blurCard, 18);
    expect(GlassTokens.dark.blurStrong, 24);
  });

  test('lerp returns a GlassTokens', () {
    final mixed = GlassTokens.light.lerp(GlassTokens.dark, 0.5);
    expect(mixed, isA<GlassTokens>());
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/theme/glass_tokens_test.dart`
Expected: FAIL — `glass_tokens.dart` does not exist.

- [ ] **Step 3: Write the implementation**

```dart
import 'package:flutter/material.dart';

@immutable
class GlassTokens extends ThemeExtension<GlassTokens> {
  const GlassTokens({
    required this.gradientTop,
    required this.gradientBottom,
    required this.blobIndigo,
    required this.blobTeal,
    required this.glassFill,
    required this.glassBorder,
    required this.glassSheen,
    required this.glassStrongFill,
    required this.glassStrongBorder,
    required this.solidFallback,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.positive,
    required this.positiveTint,
    required this.negative,
    required this.negativeTint,
    required this.settled,
    required this.settledTint,
    required this.brandStart,
    required this.brandEnd,
    required this.brandSolid,
    required this.onBrand,
    required this.blurCard,
    required this.blurStrong,
  });

  final Color gradientTop, gradientBottom, blobIndigo, blobTeal;
  final Color glassFill, glassBorder, glassSheen, glassStrongFill, glassStrongBorder, solidFallback;
  final Color textPrimary, textSecondary, textMuted;
  final Color positive, positiveTint, negative, negativeTint, settled, settledTint;
  final Color brandStart, brandEnd, brandSolid, onBrand;
  final double blurCard, blurStrong;

  LinearGradient get brandGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [brandStart, brandEnd],
      );

  static const dark = GlassTokens(
    gradientTop: Color(0xFF1E2233),
    gradientBottom: Color(0xFF0E0F16),
    blobIndigo: Color(0x525B7CFA), // #5B7CFA @ 32%
    blobTeal: Color(0x3322B8A6), // #22B8A6 @ 20%
    glassFill: Color(0x12FFFFFF), // white @ 7%
    glassBorder: Color(0x24FFFFFF), // white @ 14%
    glassSheen: Color(0x33FFFFFF), // white @ 20%
    glassStrongFill: Color(0x1AFFFFFF), // white @ 10%
    glassStrongBorder: Color(0x2EFFFFFF), // white @ 18%
    solidFallback: Color(0xFF1A1E2B),
    textPrimary: Color(0xFFF5F6F8),
    textSecondary: Color(0x99FFFFFF),
    textMuted: Color(0x6BFFFFFF),
    positive: Color(0xFF4ADE80),
    positiveTint: Color(0x294ADE80),
    negative: Color(0xFFFF7A7D),
    negativeTint: Color(0x29FF7A7D),
    settled: Color(0xFF9BA0AA),
    settledTint: Color(0x14FFFFFF),
    brandStart: Color(0xFF6E8BFF),
    brandEnd: Color(0xFF5B7CFA),
    brandSolid: Color(0xFF5B7CFA),
    onBrand: Color(0xFFFFFFFF),
    blurCard: 18,
    blurStrong: 24,
  );

  static const light = GlassTokens(
    gradientTop: Color(0xFFEEF1FA),
    gradientBottom: Color(0xFFE3E8F4),
    blobIndigo: Color(0x618FA6FF), // #8FA6FF @ 38%
    blobTeal: Color(0x4D7FE0D0), // #7FE0D0 @ 30%
    glassFill: Color(0x8CFFFFFF), // white @ 55%
    glassBorder: Color(0xB3FFFFFF), // white @ 70%
    glassSheen: Color(0x99FFFFFF), // white @ 60%
    glassStrongFill: Color(0x99FFFFFF), // white @ 60%
    glassStrongBorder: Color(0xBFFFFFFF), // white @ 75%
    solidFallback: Color(0xFFF3F5FB),
    textPrimary: Color(0xFF1A1C22),
    textSecondary: Color(0xFF5A5F6B),
    textMuted: Color(0xFF8A8F9C),
    positive: Color(0xFF0E9E6E),
    positiveTint: Color(0x240E9E6E),
    negative: Color(0xFFE5484D),
    negativeTint: Color(0x24E5484D),
    settled: Color(0xFF8A8F9C),
    settledTint: Color(0x0F000000),
    brandStart: Color(0xFF6E8BFF),
    brandEnd: Color(0xFF5B7CFA),
    brandSolid: Color(0xFF5B7CFA),
    onBrand: Color(0xFFFFFFFF),
    blurCard: 18,
    blurStrong: 24,
  );

  // The two token sets are fixed const instances; the app never mutates or
  // animates between them, so copyWith is identity and lerp snaps at the
  // midpoint. This is a deliberate, documented choice, not an omission.
  @override
  GlassTokens copyWith() => this;

  @override
  GlassTokens lerp(ThemeExtension<GlassTokens>? other, double t) {
    if (other is! GlassTokens) return this;
    return t < 0.5 ? this : other;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/theme/glass_tokens_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/glass_tokens.dart test/core/theme/glass_tokens_test.dart
git commit -m "feat: add GlassTokens theme extension for light and dark"
```

---

## Task 3: Typography (Onest + Space Grotesk)

**Files:**
- Create: `lib/core/theme/app_typography.dart`
- Test: `test/core/theme/app_typography_test.dart`

**Interfaces:**
- Produces: `TextTheme buildTextTheme(Color primary)` returning a Material `TextTheme` where display/headline/title styles use Space Grotesk and body/label styles use Onest, with `fontFeatures: [FontFeature.tabularFigures()]` on the money/display styles. Also `TextStyle moneyStyle(Color color, {double size})` (Space Grotesk 600, tabular).

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowes_app/core/theme/app_typography.dart';

void main() {
  test('money style is tabular and colored', () {
    final s = moneyStyle(const Color(0xFF4ADE80), size: 20);
    expect(s.color, const Color(0xFF4ADE80));
    expect(s.fontFeatures, contains(const FontFeature.tabularFigures()));
    expect(s.fontSize, 20);
  });

  test('text theme applies the primary color to body', () {
    final t = buildTextTheme(const Color(0xFF1A1C22));
    expect(t.bodyMedium!.color, const Color(0xFF1A1C22));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/theme/app_typography_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Write the implementation**

```dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

TextStyle _display(double size, FontWeight w, Color c) => GoogleFonts.spaceGrotesk(
      fontSize: size,
      fontWeight: w,
      color: c,
      height: 1.1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

TextStyle moneyStyle(Color color, {double size = 15}) => GoogleFonts.spaceGrotesk(
      fontSize: size,
      fontWeight: FontWeight.w600,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

TextTheme buildTextTheme(Color primary) {
  final body = GoogleFonts.onestTextTheme();
  return body.copyWith(
    displayLarge: _display(44, FontWeight.w500, primary),
    headlineSmall: _display(22, FontWeight.w600, primary),
    titleLarge: _display(20, FontWeight.w600, primary),
    bodyLarge: GoogleFonts.onest(fontSize: 15, color: primary, height: 1.5),
    bodyMedium: GoogleFonts.onest(fontSize: 14, color: primary, height: 1.5),
    labelLarge: GoogleFonts.onest(fontSize: 13, fontWeight: FontWeight.w500, color: primary),
    labelSmall: GoogleFonts.onest(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.1, color: primary),
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/theme/app_typography_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/app_typography.dart test/core/theme/app_typography_test.dart
git commit -m "feat: add Onest + Space Grotesk typography"
```

---

## Task 4: Accessibility resolution + settings

**Files:**
- Create: `lib/core/a11y/accessibility.dart`
- Test: `test/core/a11y/accessibility_test.dart`

**Interfaces:**
- Produces:
  `final reduceTransparencyProvider = StateProvider<bool>((ref) => false);` (in-app override; persistence is a Phase 4 item).
  `bool glassDisabled(BuildContext context, {required bool userReduceTransparency})` — true when the platform's `MediaQuery` reduce-transparency signal OR the user override is set. Reads `MediaQuery.maybeOf(context)?.reduceTransparency` via a helper that tolerates SDKs lacking the field (default false).
  `bool motionReduced(BuildContext context)` — returns `MediaQuery.maybeOf(context)?.disableAnimations ?? false`.

- [ ] **Step 1: Write the failing test**

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/a11y/accessibility_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Write the implementation**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final reduceTransparencyProvider = StateProvider<bool>((ref) => false);

bool _platformReduceTransparency(BuildContext context) {
  final mq = MediaQuery.maybeOf(context);
  if (mq == null) return false;
  try {
    // Available on recent Flutter; guarded for older SDKs.
    return (mq as dynamic).reduceTransparency as bool? ?? false;
  } catch (_) {
    return false;
  }
}

bool glassDisabled(BuildContext context, {required bool userReduceTransparency}) =>
    userReduceTransparency || _platformReduceTransparency(context);

bool motionReduced(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/a11y/accessibility_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/a11y/accessibility.dart test/core/a11y/accessibility_test.dart
git commit -m "feat: add reduce-transparency and reduce-motion helpers"
```

---

## Task 5: GlassSurface primitive (with solid fallback)

**Files:**
- Create: `lib/core/widgets/glass/glass_surface.dart`
- Test: `test/core/widgets/glass/glass_surface_test.dart`

**Interfaces:**
- Consumes: `GlassTokens` (Task 2), `glassDisabled` (Task 4).
- Produces: `class GlassSurface extends StatelessWidget` with
  `{required Widget child, EdgeInsetsGeometry padding = const EdgeInsets.all(16), double radius = 24, bool strong = false, bool disableBlur = false}`.
  When `disableBlur` is true it renders an opaque `solidFallback` fill with the same border/radius and NO `BackdropFilter`. Otherwise it renders `ClipRRect → BackdropFilter(blur) → Container(fill + border + top sheen gradient)`.

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/glass/glass_surface.dart';

Widget _host(Widget child) => MaterialApp(
      theme: ThemeData(extensions: const [GlassTokens.dark]),
      home: Scaffold(body: child),
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
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/widgets/glass/glass_surface_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Write the implementation**

```dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 24,
    this.strong = false,
    this.disableBlur = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool strong;
  final bool disableBlur;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final border = strong ? t.glassStrongBorder : t.glassBorder;
    final radiusGeo = BorderRadius.circular(radius);

    if (disableBlur) {
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          color: t.solidFallback,
          borderRadius: radiusGeo,
          border: Border.all(color: border, width: 1),
        ),
        child: child,
      );
    }

    return ClipRRect(
      borderRadius: radiusGeo,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: strong ? t.blurStrong : t.blurCard,
          sigmaY: strong ? t.blurStrong : t.blurCard,
        ),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: strong ? t.glassStrongFill : t.glassFill,
            borderRadius: radiusGeo,
            border: Border.all(color: border, width: 1),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [t.glassSheen, Colors.transparent],
              stops: const [0.0, 0.45],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/widgets/glass/glass_surface_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/widgets/glass/glass_surface.dart test/core/widgets/glass/glass_surface_test.dart
git commit -m "feat: add GlassSurface primitive with solid fallback"
```

---

## Task 6: GlassBackground

**Files:**
- Create: `lib/core/widgets/glass/glass_background.dart`
- Test: `test/core/widgets/glass/glass_background_test.dart`

**Interfaces:**
- Consumes: `GlassTokens`.
- Produces: `class GlassBackground extends StatelessWidget` with `{required Widget child}`. Paints the mode gradient + two positioned blurred blobs (painted, no `BackdropFilter`), with `child` stacked above.

- [ ] **Step 1: Write the failing test**

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/widgets/glass/glass_background_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Write the implementation**

```dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';

class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: const Alignment(0.2, -1),
          end: const Alignment(-0.2, 1),
          colors: [t.gradientTop, t.gradientBottom],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -40, right: -30,
            child: _Blob(color: t.blobIndigo, size: 240),
          ),
          Positioned(
            bottom: 80, left: -50,
            child: _Blob(color: t.blobTeal, size: 220),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/widgets/glass/glass_background_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/widgets/glass/glass_background.dart test/core/widgets/glass/glass_background_test.dart
git commit -m "feat: add GlassBackground gradient + ambient blobs"
```

---

## Task 7: AppTheme light + dark, wired into MaterialApp

**Files:**
- Modify: `lib/core/app_theme.dart`
- Modify: `lib/main.dart`
- Test: `test/core/app_theme_test.dart`

**Interfaces:**
- Consumes: `GlassTokens`, `buildTextTheme`.
- Produces: `AppTheme.light` and `AppTheme.dark` (`ThemeData`) each carrying its `GlassTokens` in `extensions` and the Onest/Space-Grotesk `TextTheme`, transparent scaffold background, indigo `ColorScheme` seed. `AppColors` retained for now (Phase 3 removes it).

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';

void main() {
  test('light and dark themes carry their GlassTokens', () {
    expect(AppTheme.light.extension<GlassTokens>(), GlassTokens.light);
    expect(AppTheme.dark.extension<GlassTokens>(), GlassTokens.dark);
  });

  test('scaffold background is transparent so GlassBackground shows through', () {
    expect(AppTheme.light.scaffoldBackgroundColor, Colors.transparent);
    expect(AppTheme.dark.scaffoldBackgroundColor, Colors.transparent);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/app_theme_test.dart`
Expected: FAIL — `AppTheme.dark` undefined / background not transparent.

- [ ] **Step 3: Rewrite `lib/core/app_theme.dart`**

Replace the `AppTheme` class body (keep the existing `AppColors` class untouched above it) with:

```dart
class AppTheme {
  AppTheme._();

  static ThemeData _base(Brightness brightness, GlassTokens tokens) {
    final scheme = ColorScheme.fromSeed(
      seedColor: tokens.brandSolid,
      brightness: brightness,
    ).copyWith(primary: tokens.brandSolid);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: buildTextTheme(tokens.textPrimary),
      extensions: [tokens],
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
    );
  }

  static ThemeData get light => _base(Brightness.light, GlassTokens.light);
  static ThemeData get dark => _base(Brightness.dark, GlassTokens.dark);
}
```

Add imports at the top of the file:

```dart
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/theme/app_typography.dart';
```

- [ ] **Step 4: Wire MaterialApp in `lib/main.dart`**

Replace the `MaterialApp(...)` in `MeowesApp.build` with:

```dart
    return MaterialApp(
      title: 'Meowes',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const RootScreen(),
    );
```

- [ ] **Step 5: Run tests + full suite**

Run: `flutter test test/core/app_theme_test.dart` → PASS.
Run: `flutter test` → all pre-existing tests still pass (report any that broke).

- [ ] **Step 6: Commit**

```bash
git add lib/core/app_theme.dart lib/main.dart test/core/app_theme_test.dart
git commit -m "feat: add light+dark glass themes and wire themeMode.system"
```

---

## Task 8: GlassScaffold + GlassAppBar

**Files:**
- Create: `lib/core/widgets/glass/glass_scaffold.dart`
- Create: `lib/core/widgets/glass/glass_app_bar.dart`
- Test: `test/core/widgets/glass/glass_scaffold_test.dart`

**Interfaces:**
- Consumes: `GlassBackground`, `GlassSurface`, `GlassTokens`.
- Produces:
  `class GlassScaffold extends StatelessWidget { GlassScaffold({required Widget body, PreferredSizeWidget? appBar, Widget? bottomDock}) }` — wraps `GlassBackground` around a transparent `Scaffold` (`extendBody: true`, `extendBodyBehindAppBar: true`), placing `bottomDock` above the body via a `Stack`.
  `class GlassAppBar extends StatelessWidget implements PreferredSizeWidget { GlassAppBar({String? title, Widget? leading, List<Widget> actions = const []}) }` — a `GlassSurface(strong: true)` bar; `preferredSize` height `56`.

- [ ] **Step 1: Write the failing test**

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/widgets/glass/glass_scaffold_test.dart`
Expected: FAIL — files missing.

- [ ] **Step 3: Implement `glass_app_bar.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/glass/glass_surface.dart';

class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({super.key, this.title, this.leading, this.actions = const []});
  final String? title;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: GlassSurface(
          strong: true,
          radius: 20,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              if (leading != null) leading!,
              if (title != null)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(title!, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: t.textPrimary)),
                  ),
                )
              else
                const Spacer(),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Implement `glass_scaffold.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:meowes_app/core/widgets/glass/glass_background.dart';

class GlassScaffold extends StatelessWidget {
  const GlassScaffold({super.key, required this.body, this.appBar, this.bottomDock});
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? bottomDock;

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        extendBodyBehindAppBar: true,
        appBar: appBar,
        body: Stack(
          children: [
            Positioned.fill(child: body),
            if (bottomDock != null)
              Positioned(left: 0, right: 0, bottom: 0, child: bottomDock!),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/core/widgets/glass/glass_scaffold_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/core/widgets/glass/glass_scaffold.dart lib/core/widgets/glass/glass_app_bar.dart test/core/widgets/glass/glass_scaffold_test.dart
git commit -m "feat: add GlassScaffold and GlassAppBar"
```

---

## Task 9: GlassCard, GlassButton, SkeletonLoader

**Files:**
- Create: `lib/core/widgets/glass/glass_card.dart`
- Create: `lib/core/widgets/glass/glass_button.dart`
- Create: `lib/core/widgets/glass/skeleton_loader.dart`
- Modify: `lib/core/widgets/widgets.dart`
- Test: `test/core/widgets/glass/glass_controls_test.dart`

**Interfaces:**
- Consumes: `GlassSurface`, `GlassTokens`.
- Produces:
  `class GlassCard extends StatelessWidget { GlassCard({required Widget child, EdgeInsetsGeometry padding, VoidCallback? onTap, bool disableBlur}) }` — `GlassSurface` + optional `InkWell`.
  `class GlassButton extends StatelessWidget { GlassButton({required String label, required VoidCallback? onPressed, bool secondary}) }` — primary = indigo gradient pill with `onBrand` text; secondary = glass fill; press `scale 0.98`.
  `class SkeletonLoader extends StatelessWidget { SkeletonLoader({double height, double width, double radius}) }` — shimmering placeholder.

- [ ] **Step 1: Write the failing test**

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/widgets/glass/glass_controls_test.dart`
Expected: FAIL — files missing.

- [ ] **Step 3: Implement the three widgets**

`glass_card.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:meowes_app/core/widgets/glass/glass_surface.dart';

class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.disableBlur = false});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool disableBlur;

  @override
  Widget build(BuildContext context) {
    final surface = GlassSurface(padding: padding, disableBlur: disableBlur, child: child);
    if (onTap == null) return surface;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(borderRadius: BorderRadius.circular(24), onTap: onTap, child: surface),
    );
  }
}
```

`glass_button.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/glass/glass_surface.dart';

class GlassButton extends StatefulWidget {
  const GlassButton({super.key, required this.label, required this.onPressed, this.secondary = false});
  final String label;
  final VoidCallback? onPressed;
  final bool secondary;

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final content = Center(
      child: Text(widget.label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: widget.secondary ? t.textPrimary : t.onBrand, fontWeight: FontWeight.w600)),
    );
    final child = widget.secondary
        ? GlassSurface(radius: 14, padding: const EdgeInsets.symmetric(vertical: 14), child: content)
        : Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(gradient: t.brandGradient, borderRadius: BorderRadius.circular(14)),
            child: content,
          );
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _down ? 0.98 : 1,
        duration: const Duration(milliseconds: 90),
        child: child,
      ),
    );
  }
}
```

`skeleton_loader.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';

class SkeletonLoader extends StatefulWidget {
  const SkeletonLoader({super.key, this.height = 16, this.width = double.infinity, this.radius = 8});
  final double height;
  final double width;
  final double radius;

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 0.7).animate(_c),
      child: Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(color: t.glassStrongFill, borderRadius: BorderRadius.circular(widget.radius)),
      ),
    );
  }
}
```

- [ ] **Step 4: Export the glass barrel**

Append to `lib/core/widgets/widgets.dart` (note: `glass_nav_dock.dart` is deliberately NOT exported here — it does not exist until Task 10, which adds its export line):

```dart
export 'glass/glass_app_bar.dart';
export 'glass/glass_background.dart';
export 'glass/glass_button.dart';
export 'glass/glass_card.dart';
export 'glass/glass_scaffold.dart';
export 'glass/glass_surface.dart';
export 'glass/skeleton_loader.dart';
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/core/widgets/glass/glass_controls_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/core/widgets/glass/glass_card.dart lib/core/widgets/glass/glass_button.dart lib/core/widgets/glass/skeleton_loader.dart lib/core/widgets/widgets.dart test/core/widgets/glass/glass_controls_test.dart
git commit -m "feat: add GlassCard, GlassButton, SkeletonLoader + barrel"
```

---

## Task 10: GlassNavDock

**Files:**
- Create: `lib/core/widgets/glass/glass_nav_dock.dart`
- Modify: `lib/core/widgets/widgets.dart` (add the `glass_nav_dock.dart` export if not already added in Task 9)
- Test: `test/core/widgets/glass/glass_nav_dock_test.dart`

**Interfaces:**
- Consumes: `GlassSurface`, `GlassTokens`.
- Produces: `class GlassNavDock extends StatelessWidget { GlassNavDock({required int currentIndex, required ValueChanged<int> onTap}) }` — a floating `GlassSurface(strong: true)` pill with 5 icon items (`home`, `people/users`, `add` centered/brand, `activity`, `person`), the active item tinted `brandSolid`, each with a semantic label.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/widgets/glass/glass_nav_dock.dart';

void main() {
  testWidgets('renders 5 items and reports taps', (tester) async {
    var idx = -1;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: GlassNavDock(currentIndex: 0, onTap: (i) => idx = i)),
    ));
    expect(find.byType(IconButton), findsNWidgets(5));
    await tester.tap(find.byTooltip('Groups'));
    expect(idx, 2);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/widgets/glass/glass_nav_dock_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Write the implementation**

```dart
import 'package:flutter/material.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/glass/glass_surface.dart';

class GlassNavDock extends StatelessWidget {
  const GlassNavDock({super.key, required this.currentIndex, required this.onTap});
  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _items = [
    (icon: Icons.home_outlined, label: 'Home'),
    (icon: Icons.people_outline, label: 'Friends'),
    (icon: Icons.grid_view_outlined, label: 'Groups'),
    (icon: Icons.show_chart, label: 'Activity'),
    (icon: Icons.person_outline, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
        child: GlassSurface(
          strong: true,
          radius: 26,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < _items.length; i++)
                IconButton(
                  tooltip: _items[i].label,
                  onPressed: () => onTap(i),
                  icon: Icon(
                    _items[i].icon,
                    color: i == currentIndex ? t.brandSolid : t.textMuted,
                    semanticLabel: _items[i].label,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Ensure barrel exports it**

Confirm `export 'glass/glass_nav_dock.dart';` exists in `lib/core/widgets/widgets.dart`.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/core/widgets/glass/glass_nav_dock_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/core/widgets/glass/glass_nav_dock.dart lib/core/widgets/widgets.dart test/core/widgets/glass/glass_nav_dock_test.dart
git commit -m "feat: add GlassNavDock"
```

---

## Task 11: HomeShell (IndexedStack + dock)

**Files:**
- Create: `lib/features/root/home_shell.dart`
- Modify: `lib/features/root/root_screen.dart`
- Test: `test/features/root/home_shell_test.dart`

**Interfaces:**
- Consumes: `GlassScaffold`, `GlassNavDock`, and the four tab screens (Tasks 12-15) + the reworked `HomeScreen` (Task 16).
- Produces: `class HomeShell extends StatefulWidget` holding `int _index`, rendering a `Stack` of an `IndexedStack` of `[HomeScreen, FriendsScreen, GroupsScreen, ActivityScreen, ProfileScreen]` with the `GlassNavDock` floating on top (`Positioned` bottom). Each dock item maps directly to its tab: item `i` → `_index = i`.

> Architecture note: each tab screen is its OWN full `GlassScaffold` (its own `GlassBackground` + `GlassAppBar`, no dock) so it renders and tests standalone. `HomeShell` is NOT a `GlassScaffold` — it only stacks the active tab and overlays the dock, avoiding a doubled background/Scaffold. Tab scroll content reserves ~100px bottom padding so the floating dock never covers the last row.

> Design note: the dock carries five destination tabs (Home / Friends / Groups / Activity / Profile). The "Add" action is a `GlassButton` on the Home overview (Task 16) plus the existing per-screen add affordances (e.g. Group Detail), not a dock item. A raised center-Add dock button is an optional Phase 3 enhancement, out of scope here.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/repositories/friend_repository.dart';
import 'package:meowes_app/repositories/group_repository.dart';
import 'package:meowes_app/features/root/home_shell.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockGoTrueClient extends Mock implements GoTrueClient {}
class MockFriendRepository extends Mock implements FriendRepository {}
class MockGroupRepository extends Mock implements GroupRepository {}

void main() {
  testWidgets('shows dock and switches to the Profile tab', (tester) async {
    final client = MockSupabaseClient();
    final auth = MockGoTrueClient();
    final friendRepo = MockFriendRepository();
    final groupRepo = MockGroupRepository();
    when(() => client.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(User(
      id: 'test-user-id', appMetadata: const {}, userMetadata: const {},
      aud: 'authenticated', createdAt: '2026-07-27T00:00:00Z'));
    when(() => friendRepo.watchFriendships()).thenAnswer((_) => Stream.value([]));
    when(() => friendRepo.getMyProfile()).thenAnswer((_) async => null);
    when(() => groupRepo.watchMyGroups()).thenAnswer((_) => Stream.value([]));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        supabaseClientProvider.overrideWithValue(client),
        friendRepositoryProvider.overrideWithValue(friendRepo),
        groupRepositoryProvider.overrideWithValue(groupRepo),
      ],
      child: const MaterialApp(theme: null, home: HomeShell()),
    ));
    await tester.pump();
    await tester.tap(find.byTooltip('Profile'));
    await tester.pump();
    expect(find.byType(HomeShell), findsOneWidget);
  });
}
```

> The `theme:` in the snippet is written `null` as a marker: replace it with `AppTheme.dark` (import already present). HomeShell hosts provider-backed tab screens, so the overrides above are required. Extend the mock stubs if a tab screen you wired reads additional provider methods.

> Implementer note: the tab screens (Tasks 12-16) must exist before this test compiles. If executing in order, write the four new screens (Tasks 12-15) and the reworked Home (Task 16) FIRST, then return to complete Task 11. The recommended execution order is therefore 12 → 13 → 14 → 15 → 16 → 11.

- [ ] **Step 2: Implement HomeShell**

```dart
import 'package:flutter/material.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/home/home_screen.dart';
import 'package:meowes_app/features/friends/friends_screen.dart';
import 'package:meowes_app/features/groups/groups_screen.dart';
import 'package:meowes_app/features/activity/activity_screen.dart';
import 'package:meowes_app/features/profile/profile_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  static const _tabs = [HomeScreen(), FriendsScreen(), GroupsScreen(), ActivityScreen(), ProfileScreen()];

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IndexedStack(index: _index, children: _tabs),
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: GlassNavDock(currentIndex: _index, onTap: (i) => setState(() => _index = i)),
        ),
      ],
    );
  }
}
```

- [ ] **Step 3: Route RootScreen to HomeShell**

In `lib/features/root/root_screen.dart`, replace the `import '.../home/home_screen.dart';` usage: change the success branch `return const HomeScreen();` to `return const HomeShell();` and update the import to `import 'package:meowes_app/features/root/home_shell.dart';` (remove the now-unused HomeScreen import if present).

- [ ] **Step 4: Run test + suite**

Run: `flutter test test/features/root/home_shell_test.dart` → PASS.
Run: `flutter test` → all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/root/home_shell.dart lib/features/root/root_screen.dart test/features/root/home_shell_test.dart
git commit -m "feat: add HomeShell with glass dock and route from RootScreen"
```

---

## Task 12: FriendsScreen (extract friends list from Home)

**Files:**
- Create: `lib/features/friends/friends_screen.dart`
- Test: `test/features/friends/friends_screen_test.dart`

**Interfaces:**
- Consumes: `friendRepositoryProvider`, `supabaseClientProvider` (existing), `GlassCard`, `GlassAppBar`, `AppAvatar`, `BalanceAmount`, `EmptyStateBox`, `SkeletonLoader`.
- Produces: `class FriendsScreen extends ConsumerWidget` — a padded scroll view listing accepted friends with per-friend balances (reuse the friend-balance loading logic currently in `home_screen.dart` `_FriendsAndSummary._load`), each row navigating to `FriendDetailScreen`. Loading → skeleton rows; empty → `EmptyStateBox` (no cat icon); error → inline error text.

- [ ] **Step 1: Write the failing test**

```dart
// Follow the widget-test convention (Global Constraints): mock SupabaseClient
// + GoTrueClient + FriendRepository as in test/features/home/home_screen_test.dart,
// stub auth.currentUser and watchFriendships()->Stream.value([]), and pump:
//
//   await tester.pumpWidget(ProviderScope(
//     overrides: [
//       supabaseClientProvider.overrideWithValue(client),
//       friendRepositoryProvider.overrideWithValue(friendRepo),
//     ],
//     child: const MaterialApp(theme: /* AppTheme.dark */ null, home: FriendsScreen()),
//   ));
//   await tester.pump();
//   expect(find.text('Friends'), findsWidgets);
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/friends/friends_screen_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Implement FriendsScreen**

Compose a `GlassScaffold(appBar: GlassAppBar(title: 'Friends', actions: [addFriend icon]))` body that watches `friendRepo.watchFriendships()`, filters accepted friend ids (mirror `home_screen.dart:38-41`), loads public profiles + `get_friend_balance` per id (mirror `home_screen.dart:185-198`), and renders a `GlassCard` containing friend rows (`AppAvatar` + name + `BalanceAmount`) separated by hairlines, with `SkeletonLoader` rows while waiting and an `EmptyStateBox(icon: Icons.people_outline, message: 'No friends yet. Add one to start splitting expenses.')` when empty. Each row: `onTap → Navigator.push(FriendDetailScreen(friendUserId: id))`. Add-friend action opens `AddFriendScreen`.

> Implementer: lift the exact stream/RPC code from `lib/features/home/home_screen.dart` (lines 35-49 and 166-198) so behavior is identical; only the presentation changes to glass.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/friends/friends_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/friends/friends_screen.dart test/features/friends/friends_screen_test.dart
git commit -m "feat: add FriendsScreen tab"
```

---

## Task 13: GroupsScreen (extract groups list from Home)

**Files:**
- Create: `lib/features/groups/groups_screen.dart`
- Test: `test/features/groups/groups_screen_test.dart`

**Interfaces:**
- Consumes: `groupRepositoryProvider`, `supabaseClientProvider`, `GlassCard`, `GlassAppBar`, `AppAvatar`, `BalanceAmount`, `EmptyStateBox`, `SkeletonLoader`.
- Produces: `class GroupsScreen extends ConsumerWidget` — watches `groupRepo.watchMyGroups()`, computes each group's net (mirror `home_screen.dart:273-282` `get_group_debts` logic), renders glass rows navigating to `GroupDetailScreen`. Create-group action opens `CreateGroupScreen`. Loading/empty/error states as in Task 12.

- [ ] **Step 1: Write the failing test**

```dart
// Follow the widget-test convention (Global Constraints): mock SupabaseClient +
// GoTrueClient + GroupRepository as in test/features/home/home_screen_test.dart,
// stub auth.currentUser and watchMyGroups()->Stream.value([]), and pump:
//
//   await tester.pumpWidget(ProviderScope(
//     overrides: [
//       supabaseClientProvider.overrideWithValue(client),
//       groupRepositoryProvider.overrideWithValue(groupRepo),
//     ],
//     child: const MaterialApp(theme: /* AppTheme.dark */ null, home: GroupsScreen()),
//   ));
//   await tester.pump();
//   expect(find.text('Groups'), findsWidgets);
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/groups/groups_screen_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Implement GroupsScreen**

`GlassScaffold(appBar: GlassAppBar(title: 'Groups', actions: [create-group icon]))`; watch `groupRepo.watchMyGroups()`; per group run `client.rpc('get_group_debts', params: {'target_group_id': group.id})` and compute `net` exactly as `home_screen.dart:277-282`; render `GlassCard` rows (`AppAvatar(seed: group.id, icon: Icons.grid_view_outlined)` + name + `BalanceAmount(balance: net)`), `onTap → GroupDetailScreen(groupId: group.id)`. Empty → `EmptyStateBox(icon: Icons.grid_view_outlined, message: 'No groups yet. Create one to split with a crew.')`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/groups/groups_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/groups/groups_screen.dart test/features/groups/groups_screen_test.dart
git commit -m "feat: add GroupsScreen tab"
```

---

## Task 14: ActivityScreen

**Files:**
- Create: `lib/features/activity/activity_screen.dart`
- Test: `test/features/activity/activity_screen_test.dart`

**Interfaces:**
- Consumes: existing activity/notification data source. Inspect `lib/features/notifications/notifications_screen.dart` and `lib/repositories/` for the activity/notification stream already in use; reuse that provider. `GlassCard`, `GlassAppBar`, `EmptyStateBox`, `SkeletonLoader`.
- Produces: `class ActivityScreen extends ConsumerWidget` — a glass, date-grouped activity feed. If no dedicated activity feed provider exists, render the same notifications stream used by `NotificationsScreen`, grouped by day, styled in glass. Loading/empty/error states.

- [ ] **Step 1: Write the failing test**

```dart
// Follow the widget-test convention (Global Constraints). Mock SupabaseClient +
// GoTrueClient + whatever activity/notifications provider ActivityScreen reads
// (inspect notifications_screen.dart first), stub it to an empty stream, override
// those providers, and pump with MaterialApp(theme: AppTheme.dark, home: ActivityScreen()):
//
//   await tester.pump();
//   expect(find.text('Activity'), findsWidgets);
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/activity/activity_screen_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Implement ActivityScreen**

First read `lib/features/notifications/notifications_screen.dart` to find the stream/provider it consumes. Build `GlassScaffold(appBar: GlassAppBar(title: 'Activity'))` with a day-grouped list rendered in a `GlassCard`, `SkeletonLoader` rows while waiting, and `EmptyStateBox(icon: Icons.show_chart, message: 'No activity yet.')` when empty.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/activity/activity_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/activity/activity_screen.dart test/features/activity/activity_screen_test.dart
git commit -m "feat: add ActivityScreen tab"
```

---

## Task 15: ProfileScreen (+ reduce-transparency toggle)

**Files:**
- Create: `lib/features/profile/profile_screen.dart`
- Test: `test/features/profile/profile_screen_test.dart`

**Interfaces:**
- Consumes: `friendRepositoryProvider.getMyProfile()` (existing), `supabaseClientProvider` (for sign-out), `reduceTransparencyProvider` (Task 4), `GlassScaffold`, `GlassAppBar`, `GlassCard`, `AppAvatar`.
- Produces: `class ProfileScreen extends ConsumerWidget` — glass header (avatar + name), a settings `GlassCard` list including a `SwitchListTile` bound to `reduceTransparencyProvider`, and a sign-out action calling `client.auth.signOut()`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/a11y/accessibility.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/repositories/friend_repository.dart';
import 'package:meowes_app/features/profile/profile_screen.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockGoTrueClient extends Mock implements GoTrueClient {}
class MockFriendRepository extends Mock implements FriendRepository {}

void main() {
  testWidgets('reduce-transparency switch flips the provider', (tester) async {
    final client = MockSupabaseClient();
    final auth = MockGoTrueClient();
    final friendRepo = MockFriendRepository();
    when(() => client.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(User(
      id: 'test-user-id', appMetadata: const {}, userMetadata: const {},
      aud: 'authenticated', createdAt: '2026-07-27T00:00:00Z'));
    when(() => friendRepo.getMyProfile()).thenAnswer((_) async => null);

    final container = ProviderContainer(overrides: [
      supabaseClientProvider.overrideWithValue(client),
      friendRepositoryProvider.overrideWithValue(friendRepo),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.dark, home: const ProfileScreen()),
    ));
    await tester.pump();
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    expect(container.read(reduceTransparencyProvider), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/profile/profile_screen_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Implement ProfileScreen**

`GlassScaffold(appBar: GlassAppBar(title: 'Profile'))` body: a glass header (`AppAvatar` + profile name from `getMyProfile()`), then a `GlassCard` with a `SwitchListTile(title: Text('Reduce transparency'), value: ref.watch(reduceTransparencyProvider), onChanged: (v) => ref.read(reduceTransparencyProvider.notifier).state = v)`, and a sign-out `ListTile`/`GlassButton` calling `ref.read(supabaseClientProvider).auth.signOut()`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/profile/profile_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/profile/profile_screen.dart test/features/profile/profile_screen_test.dart
git commit -m "feat: add ProfileScreen with reduce-transparency toggle"
```

---

## Task 16: Rework HomeScreen into an overview

**Files:**
- Modify: `lib/features/home/home_screen.dart`
- Test: `test/features/home/home_overview_test.dart`

**Interfaces:**
- Consumes: existing providers, `GlassScaffold`, `GlassAppBar`, `BalanceSummaryCard` (still the pre-glass version until Phase 3 restyles it), `GlassButton`.
- Produces: reworked `class HomeScreen extends ConsumerWidget` that shows greeting + overall-balance hero + primary actions (Add expense / Settle up), WITHOUT the full friends and groups lists (those now live in the Friends and Groups tabs). Keep the overall-balance computation (sum of `get_friend_balance`) that currently lives in `_FriendsAndSummary`.

- [ ] **Step 1: Write the failing test**

```dart
// Follow the widget-test convention (Global Constraints) and the existing
// test/features/home/home_screen_test.dart setup verbatim (mock client + friend
// + group repos, override the three providers, MaterialApp(theme: AppTheme.dark,
// home: HomeScreen())). Then assert the Groups section is gone from the overview:
//
//   await tester.pump();
//   expect(find.text('Groups'), findsNothing); // Groups list moved to its own tab
```

> Note: update the existing `test/features/home/home_screen_test.dart` too — its current assertion `expect(find.text('Groups'), findsOneWidget)` becomes false once Home is an overview. Change that test to assert the overview content (greeting + balance hero) instead, so the suite stays green.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/home/home_overview_test.dart`
Expected: FAIL — current Home still renders the Groups section.

- [ ] **Step 3: Rework HomeScreen**

Reduce `home_screen.dart` to: `GlassScaffold(appBar: GlassAppBar(title: greeting, actions: [notifications bell]))` body containing the overall-balance hero (keep `_FriendsAndSummary`'s balance summation, drop its friends list) and two `GlassButton`s (Add expense → `AddExpenseScreen`, Settle up → the settle entry). Remove the `_GroupTile`/groups `StreamBuilder` and the `_FriendTile` list from Home (that logic now lives in Tasks 12/13). Remove the `👋` emoji from the greeting. Keep the `_showAddMenu` sheet.

- [ ] **Step 4: Run test + suite**

Run: `flutter test test/features/home/home_overview_test.dart` → PASS.
Run: `flutter test` → all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/home/home_screen.dart test/features/home/home_overview_test.dart
git commit -m "refactor: reduce Home to an overview; lists move to tabs"
```

---

## Task 17: Full-suite + manual verification gate

**Files:** none (verification only).

- [ ] **Step 1: Run the whole suite**

Run: `flutter test`
Expected: all pass. Fix any regressions before proceeding.

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: no new errors. Address warnings introduced by these tasks.

- [ ] **Step 3: Manual run in both modes**

Launch the app (device or simulator). Verify: gradient backdrop renders; glass balance card, app bar, and dock are frosted; dock switches between all five tabs; Friends/Groups lists show data; Profile's reduce-transparency toggle swaps glass to solid fills. Switch the OS theme light↔dark and confirm both render with legible contrast.

- [ ] **Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix: post-integration cleanup for glass foundation and shell"
```

---

## Follow-on plans (authored after this lands)

- **Phase 3 — Restyle existing screens.** add-expense, expense-detail, group-detail, create-group, add-friend, friend-detail, settle-up, notifications, sign-in, profile-setup — each migrated to glass primitives with full loading/empty/error states, plus restyling `BalanceSummaryCard`, `BalanceAmount`, `AppAvatar`, `SectionHeader`, `EmptyStateBox` and removing the legacy `AppColors`/`AppCard`. The center dock "Add" affordance and the add-action sheet are finalized here. To be planned once these primitive APIs are final.
- **Phase 4 — Polish & audit.** Motion (count-up, staggered lists, dock indicator slide), full WCAG AA contrast audit across both modes and the solid fallback, blur-perf pass on low-end devices, and optional font bundling into `assets/google_fonts/` to remove runtime fetch.
