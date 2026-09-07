// lib/features/auth/sign_in_screen.dart

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:meowes_app/core/a11y/accessibility.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/util/svg_path.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/repositories/auth_repository.dart';
import 'package:meowes_app/features/root/root_screen.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseClientProvider)),
);

/// Sage accent used only on this screen's illustration furniture (glow, paw
/// prints, feature bubbles). Alpha-blended so it reads on cream and espresso.
const _sage = Color(0xFF7A9A65);

/// True only in a build made with `--dart-define=MEOWES_REVIEW=1`, used to
/// expose the seeded test-account sign-in for app-store review.
const _reviewBuild =
    bool.fromEnvironment('MEOWES_REVIEW', defaultValue: false);

class SignInScreen extends ConsumerWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authRepo = ref.watch(authRepositoryProvider);
    final t = Theme.of(context).extension<GlassTokens>()!;

    Future<void> handleSignIn(Future<void> Function() signIn) async {
      try {
        await signIn();
      } on SignInWithAppleAuthorizationException catch (e) {
        // User backed out of the Apple sheet — not an error worth surfacing.
        if (e.code == AuthorizationErrorCode.canceled) return;
        if (context.mounted) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(const SnackBar(
                content: Text('Apple sign-in failed. Please try again.')));
        }
        return;
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(const SnackBar(
                content: Text('Sign-in failed. Please try again.')));
        }
        return;
      }
      if (context.mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const RootScreen()),
        );
      }
    }

    final showApple = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    return GlassScaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            children: [
              const _HeroCat(),
              const SizedBox(height: 4),
              const _Wordmark(),
              const SizedBox(height: 10),
              Text(
                'Split expenses. Stronger friendships.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: t.textSecondary),
              ),
              const SizedBox(height: 26),
              const _HowItWorksCard(),
              const SizedBox(height: 26),
              _AuthButton(
                label: 'Continue with Google',
                icon: const _GoogleMark(),
                primary: true,
                onTap: () => handleSignIn(authRepo.signInWithGoogle),
              ),
              if (showApple) ...[
                const SizedBox(height: 12),
                _AuthButton(
                  label: 'Continue with Apple',
                  icon: Icon(Icons.apple, size: 24, color: t.textPrimary),
                  primary: false,
                  onTap: () => handleSignIn(authRepo.signInWithApple),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified_user_outlined,
                      size: 15, color: _sage.withValues(alpha: 0.8)),
                  const SizedBox(width: 7),
                  Text(
                    'Secure. Private. Made for friends.',
                    style: TextStyle(fontSize: 13, color: t.textSecondary),
                  ),
                ],
              ),
              // Shown in debug builds, and in a review build produced with
              // `--dart-define=MEOWES_REVIEW=1` so app-store reviewers can
              // sign in without a Google/Apple account (P0-3 in
              // docs/store_readiness.md).
              if (kDebugMode || _reviewBuild) ...[
                const SizedBox(height: 24),
                Divider(color: t.textMuted.withValues(alpha: 0.2)),
                const SizedBox(height: 4),
                Text(_reviewBuild ? 'Reviewer sign-in' : 'Dev tools',
                    style: TextStyle(color: t.textMuted, fontSize: 12)),
                TextButton(
                  onPressed: () => handleSignIn(
                    () => authRepo.signInWithTestAccount(
                        'testuser1@meowes.dev', 'MeowesDevTest123!'),
                  ),
                  child: Text('Sign in as Test User 1',
                      style: TextStyle(color: t.textSecondary)),
                ),
                TextButton(
                  onPressed: () => handleSignIn(
                    () => authRepo.signInWithTestAccount(
                        'testuser2@meowes.dev', 'MeowesDevTest123!'),
                  ),
                  child: Text('Sign in as Test User 2',
                      style: TextStyle(color: t.textSecondary)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Kitten peeking over a rounded cream ledge, backed by a soft sage glow and
/// scattered paw prints / sparkles.
class _HeroCat extends StatelessWidget {
  const _HeroCat();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return SizedBox(
      height: 220,
      // Clip.none so the wash and the ledge can bleed past the page padding to
      // the screen edges instead of ending on a hard vertical seam.
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          // Broad sage wash filling the space behind the cat. Blurred rather
          // than gradient-faded so it has no perceptible boundary.
          Positioned(
            left: 22,
            right: 22,
            top: 14,
            bottom: 46,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(60),
                  color: _sage.withValues(alpha: 0.26),
                ),
              ),
            ),
          ),
          const Positioned.fill(child: _PawScatter()),
          const Positioned(left: -8, top: -6, child: _LeafBranch()),
          // Outlined heart drifting at the top right.
          Positioned(
            right: 46,
            top: 2,
            child: Icon(
              Icons.favorite_border,
              size: 20,
              color: _sage.withValues(alpha: 0.5),
            ),
          ),
          // Chat bubbles either side of the kitten's head.
          const Positioned(
            left: 0,
            top: 44,
            child: _ChatBubble(
              tailOnRight: true,
              child: Icon(Icons.favorite, size: 20, color: _sage),
            ),
          ),
          const Positioned(
            right: 0,
            top: 62,
            child: _ChatBubble(
              tailOnRight: false,
              child: _Coin(size: 30),
            ),
          ),
          // The ledge, drawn behind the cat so the paws hang over its edge. It
          // extends past the hero and dissolves downward, so only the rounded
          // top reads as an edge and the bottom melts into the page.
          Positioned(
            left: -24,
            right: -24,
            bottom: -26,
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white, Colors.white, Colors.transparent],
                stops: [0.0, 0.34, 1.0],
              ).createShader(rect),
              child: Container(
                height: 68,
                decoration: BoxDecoration(
                  color: t.cardColor.withValues(alpha: 0.92),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(44),
                  ),
                ),
              ),
            ),
          ),
          // Kitten, paws resting on the ledge.
          Positioned(
            bottom: 4,
            child: Image.asset(
              'assets/images/cat.png',
              height: 195,
              fit: BoxFit.contain,
              semanticLabel: 'Meowes kitten',
            ),
          ),
        ],
      ),
    );
  }
}

/// Rounded speech bubble with a small tail, used for the heart and coin that
/// float either side of the kitten.
class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.child, required this.tailOnRight});

  final Widget child;

  /// Which bottom corner the tail points from — toward the cat in both cases.
  final bool tailOnRight;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final fill = Color.lerp(t.cardColor, Colors.white, 0.5)!;
    // The tail is a rotated square drawn under the body so the overlapping
    // half is hidden and the two read as one shape.
    return SizedBox(
      width: 56,
      height: 52,
      child: Stack(
        children: [
          Positioned(
            bottom: 0,
            left: tailOnRight ? null : 9,
            right: tailOnRight ? 9 : null,
            child: Transform.rotate(
              angle: 0.785,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: t.cardShadow,
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// Olive sprig: a stem with a few leaves, hanging into the top-left corner.
class _LeafBranch extends StatelessWidget {
  const _LeafBranch();

  // (dx, dy, rotation, size)
  static const _leaves = <(double, double, double, double)>[
    (0, 0, 2.5, 26),
    (22, 14, 2.9, 20),
    (6, 30, 2.2, 17),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      height: 60,
      child: Stack(
        children: [
          for (final (dx, dy, angle, size) in _leaves)
            Positioned(
              left: dx,
              top: dy,
              child: Transform.rotate(
                angle: angle,
                child: Icon(
                  Icons.eco,
                  size: size,
                  color: _sage.withValues(alpha: 0.42),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Faint paw prints sprinkled around the hero.
class _PawScatter extends StatelessWidget {
  const _PawScatter();

  // (xFraction, yFraction, size)
  static const _marks = <(double, double, double)>[
    (0.03, 0.42, 20),
    (0.10, 0.62, 15),
    (0.15, 0.30, 13),
    (0.90, 0.55, 18),
    (0.95, 0.34, 13),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return LayoutBuilder(
      builder: (context, c) => Stack(
        children: [
          for (final (fx, fy, size) in _marks)
            Positioned(
              left: fx * c.maxWidth,
              top: fy * c.maxHeight,
              child: Transform.rotate(
                angle: (fx - 0.5) * 0.9,
                child: Icon(
                  Icons.pets,
                  size: size,
                  color: t.textMuted.withValues(alpha: 0.22),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Meowes" wordmark — the first `o` carries a paw print.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final style = Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontSize: 52,
          height: 1.0,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.5,
          color: t.textPrimary,
        );
    // Bottom-aligned rather than baseline-aligned: a Stack reports no text
    // baseline, so CrossAxisAlignment.baseline drops the `o`. Every run here
    // shares one line height and none of the glyphs descend, so aligning the
    // bottoms puts the baselines in the same place.
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('Me', style: style),
        Stack(
          alignment: Alignment.center,
          children: [
            Text('o', style: style),
            // The Stack centres on the full line box, but the `o`'s counter
            // sits low in it — nudge the paw down onto the counter.
            Transform.translate(
              offset: const Offset(0, 5),
              child: Icon(Icons.pets, size: 11, color: t.cardColor),
            ),
          ],
        ),
        Text('wes', style: style),
      ],
    );
  }
}

/// Three-step explainer: split bills → care for your cat → earn coins.
class _HowItWorksCard extends StatelessWidget {
  const _HowItWorksCard();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(8, 22, 8, 16),
      radius: 32,
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: _Step(
                  title: 'Add & Split Bills',
                  body: 'Add expenses and split easily with friends',
                  bubble: _ReceiptBubble(),
                ),
              ),
              const _DashArrow(),
              const Expanded(
                child: _Step(
                  title: 'Care for Your Cat',
                  body: 'Spend time with your cat and earn coins',
                  bubble: _CatBubble(),
                ),
              ),
              const _DashArrow(),
              const Expanded(
                child: _Step(
                  title: 'Earn & Use Coins',
                  body: 'Settle up and earn more coins for your cat',
                  bubble: _CoinBubble(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: _sage.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.card_giftcard, size: 15, color: _sage),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Settle balances = More rewards for your cat!',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: t.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.pets, size: 15, color: _sage),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.title, required this.body, required this.bubble});

  final String title;
  final String body;
  final Widget bubble;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return Column(
      children: [
        bubble,
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 1,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
            color: t.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          textAlign: TextAlign.center,
          style:
              TextStyle(fontSize: 9.5, height: 1.35, color: t.textSecondary),
        ),
      ],
    );
  }
}

/// Round tinted disc that holds each step's icon.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.child, this.tint = _sage, this.strength = 0.20});

  final Widget child;
  final Color tint;

  /// Peak alpha of the tint at the disc's edge.
  final double strength;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 68,
      height: 68,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            tint.withValues(alpha: strength * 0.3),
            tint.withValues(alpha: strength),
          ],
        ),
      ),
      child: child,
    );
  }
}

class _ReceiptBubble extends StatelessWidget {
  const _ReceiptBubble();

  @override
  Widget build(BuildContext context) => const _Bubble(
        child: Icon(Icons.receipt_long, size: 32, color: _sage),
      );
}

class _CatBubble extends StatelessWidget {
  const _CatBubble();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 68,
      height: 76,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          _Bubble(
            child: ClipOval(
              child: Image.asset(
                'assets/images/cat.png',
                width: 58,
                height: 58,
                fit: BoxFit.cover,
                alignment: const Alignment(0, -0.35),
              ),
            ),
          ),
          const Positioned(
            top: 0,
            child: Icon(Icons.favorite, size: 16, color: _sage),
          ),
        ],
      ),
    );
  }
}

class _CoinBubble extends StatelessWidget {
  const _CoinBubble();

  @override
  Widget build(BuildContext context) {
    return const _Bubble(
      tint: Color(0xFFE0A21A),
      strength: 0.10,
      child: _Coin(),
    );
  }
}

/// Gold paw coin.
class _Coin extends StatelessWidget {
  const _Coin({this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFD770), Color(0xFFE8A317)],
        ),
      ),
      child: Container(
        width: size * 0.75,
        height: size * 0.75,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x33FFFFFF), width: 1.5),
        ),
        child: Icon(Icons.pets, size: size * 0.4, color: const Color(0xFF8A5B08)),
      ),
    );
  }
}

/// Dashed connector with an arrowhead, sitting level with the step bubbles.
class _DashArrow extends StatelessWidget {
  const _DashArrow();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final color = t.textMuted.withValues(alpha: 0.55);
    return Padding(
      padding: const EdgeInsets.only(top: 30),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            Container(width: 3.5, height: 1.5, color: color),
            const SizedBox(width: 2.5),
          ],
          Icon(Icons.arrow_forward_ios, size: 9, color: color),
        ],
      ),
    );
  }
}

/// Full-width pill CTA with a leading brand mark, matching [PillButton]'s
/// press feedback and shadow treatment.
class _AuthButton extends StatefulWidget {
  const _AuthButton({
    required this.label,
    required this.icon,
    required this.primary,
    required this.onTap,
  });

  final String label;
  final Widget icon;
  final bool primary;
  final VoidCallback? onTap;

  @override
  State<_AuthButton> createState() => _AuthButtonState();
}

class _AuthButtonState extends State<_AuthButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap == null) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = widget.primary
        ? t.brandSolid
        : Color.lerp(t.cardColor, Colors.white, isDark ? 0.14 : 0.6)!;
    final fg = widget.primary ? t.onBrand : t.textPrimary;
    final reduceMotion = motionReduced(context);

    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1.0,
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 100),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(32),
              border: widget.primary
                  ? null
                  : Border.all(color: t.textPrimary.withValues(alpha: 0.06)),
              boxShadow: [
                BoxShadow(
                  color: t.cardShadow,
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  widget.label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Positioned(left: 0, child: widget.icon),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The official four-colour Google "G" on a white disc.
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: const SizedBox(
        width: 18,
        height: 18,
        child: CustomPaint(painter: _GoogleGPainter()),
      ),
    );
  }
}

/// Renders the Google "G" from its official SVG path data (24×24 viewBox).
class _GoogleGPainter extends CustomPainter {
  const _GoogleGPainter();

  static const _blue = Color(0xFF4285F4);
  static const _green = Color(0xFF34A853);
  static const _yellow = Color(0xFFFBBC05);
  static const _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24.0, size.height / 24.0);
    final paint = Paint()..isAntiAlias = true;

    canvas.drawPath(
      parseSvgPath(
        'M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 '
        '2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z',
      ),
      paint..color = _blue,
    );
    canvas.drawPath(
      parseSvgPath(
        'M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 '
        '1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 '
        '7.7 23 12 23z',
      ),
      paint..color = _green,
    );
    canvas.drawPath(
      parseSvgPath(
        'M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 '
        '8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z',
      ),
      paint..color = _yellow,
    );
    canvas.drawPath(
      parseSvgPath(
        'M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 '
        '1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z',
      ),
      paint..color = _red,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GoogleGPainter oldDelegate) => false;
}
