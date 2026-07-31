import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/a11y/accessibility.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/repositories/pet_repository.dart';

enum _PettingPhase { idle, petting, content }

class _TrailPoint {
  final Offset position;
  final int createdAtMs;
  _TrailPoint(this.position, this.createdAtMs);
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

  void _onPanStart(DragStartDetails details) {
    if (_busy) return;
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
                                color: t.positive,
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

/// Paints the fading swipe trail: each recent touch point rendered as a
/// dot whose opacity decays linearly with age, giving a comet-tail effect.
class _TrailPainter extends CustomPainter {
  final List<_TrailPoint> trail;
  final int nowMs;
  final int fadeMs;
  final Color color;
  _TrailPainter({
    required this.trail,
    required this.nowMs,
    required this.fadeMs,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final point in trail) {
      final age = nowMs - point.createdAtMs;
      final opacity = (1 - age / fadeMs).clamp(0.0, 1.0);
      if (opacity <= 0) continue;
      final paint = Paint()
        ..color = color.withValues(alpha: opacity * 0.7)
        ..strokeCap = StrokeCap.round;
      canvas.drawCircle(point.position, 10, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TrailPainter oldDelegate) => true;
}
