import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/a11y/accessibility.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/repositories/pet_repository.dart';

enum _PettingPhase { idle, petting, content }

/// Warm gold palette for the petting trail — matches the coin/sparkle gold
/// used elsewhere in the app (see `_Coin` on the sign-in screen) rather than
/// the balance-positive green, since this is a delight effect, not money.
const _kGoldCore = Color(0xFFFFE39A);
const _kGoldMid = Color(0xFFFFC24D);
const _kGoldDeep = Color(0xFFC08B1E);

final _sparkleRandom = math.Random();

class _TrailPoint {
  final Offset position;
  final int createdAtMs;

  /// Small fixed jitter offsets + sizes for the pixie-dust specks scattered
  /// around this point, generated once at creation so they don't swim
  /// around on repaint — only their fade (driven by age) animates.
  final List<Offset> sparkleOffsets;
  final List<double> sparkleSizes;
  final double twinklePhase;

  _TrailPoint(this.position, this.createdAtMs)
      : sparkleOffsets = List.generate(
          2,
          (_) => Offset(
            (_sparkleRandom.nextDouble() - 0.5) * 40,
            (_sparkleRandom.nextDouble() - 0.5) * 40,
          ),
        ),
        sparkleSizes = List.generate(
          2,
          (_) => 1.2 + _sparkleRandom.nextDouble() * 1.8,
        ),
        twinklePhase = _sparkleRandom.nextDouble() * math.pi * 2;
}

/// Dedicated full-screen petting interaction: drag over the cat's head to
/// leave a fading trail; releasing settles the cat into a content pose and
/// fires one `petTheCat()` call — the whole gesture counts as one pet
/// action, matching the app's existing single-tap semantics.
class PetInteractionScreen extends ConsumerStatefulWidget {
  const PetInteractionScreen({super.key});

  @override
  ConsumerState<PetInteractionScreen> createState() =>
      _PetInteractionScreenState();
}

class _PetInteractionScreenState extends ConsumerState<PetInteractionScreen>
    with SingleTickerProviderStateMixin {
  static const _trailFadeMs = 350;

  /// Below this cumulative path length, a completed drag reads as finger
  /// jitter on a tap rather than an intentional petting stroke, so it's
  /// discarded instead of counting as a pet.
  static const _minSwipeDistance = 24.0;

  /// Cat's head bounding box as a fraction of the source image (1024x1536),
  /// covering ears through chin/upper neck across the idle and petting
  /// frames — swipes must start inside this box to count as petting.
  static const _headImageSize = Size(1024, 1536);
  static const _headZoneFraction = Rect.fromLTRB(0.15, 0.12, 0.85, 0.58);

  final GlobalKey _petAreaKey = GlobalKey();

  _PettingPhase _phase = _PettingPhase.idle;
  final List<_TrailPoint> _trail = [];
  late final Ticker _ticker;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (_trail.isEmpty) return;
    final now = elapsed.inMilliseconds;
    final before = _trail.length;
    _trail.removeWhere((p) => now - p.createdAtMs > _trailFadeMs);
    if (_trail.length != before || _phase == _PettingPhase.petting) {
      setState(() {});
    }
  }

  /// Maps the cat's head from source-image fractions to on-screen
  /// coordinates, accounting for `BoxFit.cover` scaling/cropping of
  /// [_headImageSize] into [viewSize].
  Rect _headZone(Size viewSize) {
    final scale = math.max(
      viewSize.width / _headImageSize.width,
      viewSize.height / _headImageSize.height,
    );
    final scaledWidth = _headImageSize.width * scale;
    final scaledHeight = _headImageSize.height * scale;
    final dx = (viewSize.width - scaledWidth) / 2;
    final dy = (viewSize.height - scaledHeight) / 2;
    return Rect.fromLTRB(
      dx + _headZoneFraction.left * scaledWidth,
      dy + _headZoneFraction.top * scaledHeight,
      dx + _headZoneFraction.right * scaledWidth,
      dy + _headZoneFraction.bottom * scaledHeight,
    );
  }

  Size? get _petAreaSize {
    final box = _petAreaKey.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box.size : null;
  }

  double _trailPathLength() {
    var total = 0.0;
    for (var i = 1; i < _trail.length; i++) {
      total += (_trail[i].position - _trail[i - 1].position).distance;
    }
    return total;
  }

  void _onPanStart(DragStartDetails details) {
    if (_busy) return;
    final size = _petAreaSize;
    if (size == null || !_headZone(size).contains(details.localPosition)) {
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _phase = _PettingPhase.petting;
      _trail
        ..clear()
        ..add(
          _TrailPoint(details.localPosition, _ticker.isActive ? _nowMs() : 0),
        );
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_phase != _PettingPhase.petting) return;
    _trail.add(_TrailPoint(details.localPosition, _nowMs()));
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  Future<void> _onPanEnd(DragEndDetails details) async {
    if (_phase != _PettingPhase.petting || _busy) return;
    if (_trail.length < 2 || _trailPathLength() < _minSwipeDistance) {
      setState(() {
        _phase = _PettingPhase.idle;
        _trail.clear();
      });
      return;
    }
    setState(() {
      _phase = _PettingPhase.content;
      _busy = true;
    });
    HapticFeedback.lightImpact();
    try {
      await ref.read(petRepositoryProvider).petTheCat();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await Future.delayed(const Duration(milliseconds: 1400));
    if (mounted) {
      setState(() {
        _phase = _PettingPhase.idle;
        _trail.clear();
      });
    }
  }

  String get _catAsset {
    switch (_phase) {
      case _PettingPhase.idle:
        return 'assets/images/pet/cat_idle.png';
      case _PettingPhase.petting:
        return 'assets/images/pet/cat_petting.png';
      case _PettingPhase.content:
        return 'assets/images/pet/cat_content.png';
    }
  }

  String get _pillLabel {
    switch (_phase) {
      case _PettingPhase.idle:
        return 'Swipe over their head';
      case _PettingPhase.petting:
        return 'They love it! Keep going';
      case _PettingPhase.content:
        return 'Purrfect!';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final reduceMotion = motionReduced(context);

    return GlassScaffold(
      appBar: const GlassAppBar(title: 'Pet'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            children: [
              Text(
                'Stroke, cuddle, make them happy',
                style: TextStyle(color: t.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: GestureDetector(
                  key: _petAreaKey,
                  behavior: HitTestBehavior.opaque,
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  child: SoftCard(
                    padding: EdgeInsets.zero,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.asset('assets/bg-1.png', fit: BoxFit.cover),
                          AnimatedSwitcher(
                            duration: reduceMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 250),
                            child: Image.asset(
                              _catAsset,
                              key: ValueKey(_catAsset),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stack) =>
                                  Container(
                                    color: t.textPrimary.withValues(
                                      alpha: 0.06,
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      Icons.pets,
                                      size: 96,
                                      color: t.textSecondary,
                                    ),
                                  ),
                            ),
                          ),
                          if (!reduceMotion)
                            CustomPaint(
                              painter: _TrailPainter(
                                trail: _trail,
                                nowMs: _nowMs(),
                                fadeMs: _trailFadeMs,
                              ),
                            ),
                          Positioned(
                            bottom: 20,
                            left: 20,
                            right: 20,
                            child: _PillLabel(
                              text: _pillLabel,
                              color: t.positive,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillLabel extends StatelessWidget {
  final String text;
  final Color color;
  const _PillLabel({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    );
  }
}

/// Paints the swipe trail as a golden, auto-fading pixie-dust trace: a
/// tapering glow line along the actual swipe trajectory, with tiny gold/
/// white sparkle specks scattered along it. Both the line and the specks
/// fade purely by age (`fadeMs`), so the trail always reads as freshly
/// sprinkled dust dissolving behind the finger, never a static shape.
class _TrailPainter extends CustomPainter {
  final List<_TrailPoint> trail;
  final int nowMs;
  final int fadeMs;
  _TrailPainter({required this.trail, required this.nowMs, required this.fadeMs});

  double _opacityOf(_TrailPoint p) {
    final age = nowMs - p.createdAtMs;
    return (1 - age / fadeMs).clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (trail.isEmpty) return;

    // Trajectory line: one segment per consecutive pair, each with its own
    // opacity/width so the tail dissolves smoothly rather than popping off
    // point-by-point. Two passes per segment — a soft wide glow, then a
    // slim bright core — for a warm, luminous stroke instead of a flat line.
    for (var i = 1; i < trail.length; i++) {
      final a = trail[i - 1];
      final b = trail[i];
      final opacity = math.min(_opacityOf(a), _opacityOf(b));
      if (opacity <= 0) continue;

      canvas.drawLine(
        a.position,
        b.position,
        Paint()
          ..color = _kGoldMid.withValues(alpha: opacity * 0.28)
          ..strokeWidth = 14 * opacity
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawLine(
        a.position,
        b.position,
        Paint()
          ..color = _kGoldCore.withValues(alpha: opacity * 0.9)
          ..strokeWidth = 3 * opacity + 0.5
          ..strokeCap = StrokeCap.round,
      );
    }

    // Pixie dust: tiny four-point sparkle glints scattered around each
    // point, twinkling as they fade.
    for (final point in trail) {
      final opacity = _opacityOf(point);
      if (opacity <= 0) continue;
      final twinkle = 0.6 + 0.4 * math.sin(nowMs / 90 + point.twinklePhase);

      for (var i = 0; i < point.sparkleOffsets.length; i++) {
        final center = point.position + point.sparkleOffsets[i];
        final radius = point.sparkleSizes[i] * (0.5 + 0.5 * opacity);
        final alpha = (opacity * twinkle).clamp(0.0, 1.0);
        if (alpha <= 0) continue;
        _drawSparkle(canvas, center, radius, alpha);
      }
    }
  }

  void _drawSparkle(Canvas canvas, Offset center, double radius, double alpha) {
    final glow = Paint()
      ..color = _kGoldDeep.withValues(alpha: alpha * 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.4);
    canvas.drawCircle(center, radius * 1.3, glow);

    // Sharp four-point glint — thin spikes with a tight concave waist, so
    // several overlapping sparkles read as scattered glints rather than
    // fusing into a solid patch.
    final path = Path()
      ..moveTo(center.dx, center.dy - radius * 2.4)
      ..lineTo(center.dx + radius * 0.35, center.dy - radius * 0.35)
      ..lineTo(center.dx + radius * 2.4, center.dy)
      ..lineTo(center.dx + radius * 0.35, center.dy + radius * 0.35)
      ..lineTo(center.dx, center.dy + radius * 2.4)
      ..lineTo(center.dx - radius * 0.35, center.dy + radius * 0.35)
      ..lineTo(center.dx - radius * 2.4, center.dy)
      ..lineTo(center.dx - radius * 0.35, center.dy - radius * 0.35)
      ..close();
    canvas.drawPath(path, Paint()..color = _kGoldMid.withValues(alpha: alpha * 0.8));
    canvas.drawCircle(center, radius * 0.35, Paint()..color = Colors.white.withValues(alpha: alpha * 0.85));
  }

  @override
  bool shouldRepaint(covariant _TrailPainter oldDelegate) => true;
}
