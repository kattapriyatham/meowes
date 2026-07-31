import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/models/food.dart';
import 'package:meowes_app/models/pet.dart';
import 'package:meowes_app/repositories/pet_repository.dart';

/// Minimum time between feeds — mirrors the cooldown check in
/// `feed_pet()` (supabase/migrations/20260730090000_feed_pet_food_choice.sql).
/// Duplicated here so the screen can disable dragging and show a countdown
/// up front, instead of only finding out reactively via
/// [FeedCooldownException] after a drop.
const _feedCooldown = Duration(hours: 3);

/// Dev/test-only escape hatch: `flutter run --dart-define=FEED_TESTING_UNLIMITED=true`
/// skips the *client-side* cooldown gate below so the drop zone stays live
/// for repeat testing. It can't bypass the server-side check in
/// `feed_pet()` — that RPC enforces the real 3-hour cooldown regardless, so
/// a `feed()` call against a pet fed within the window still throws
/// [FeedCooldownException] even with this set.
const _bypassFeedCooldown = bool.fromEnvironment('FEED_TESTING_UNLIMITED');

/// Single-screen feeding flow: drag any of the three foods straight onto
/// the cat to feed it — no separate "choose food" or "place food" screens.
/// Eating plays out in place, then a "Yum!" bottom sheet summarizes the
/// reward and the screen pops back. If the cooldown from the last feed is
/// still active, dragging is disabled and a countdown is shown instead.
class FeedFlowScreen extends ConsumerStatefulWidget {
  const FeedFlowScreen({super.key, required this.pet});
  final Pet pet;

  @override
  ConsumerState<FeedFlowScreen> createState() => _FeedFlowScreenState();
}

class _FeedFlowScreenState extends ConsumerState<FeedFlowScreen> {
  late Pet _pet;
  bool _eating = false;
  bool _hovering = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _pet = widget.pet;
    // Only needed to tick the countdown text/progress bar down while the
    // cooldown banner is showing; re-checked each tick via _cooldownRemaining
    // rather than tracked as separate state.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Duration? get _cooldownRemaining {
    if (_bypassFeedCooldown) return null;
    final lastFed = _pet.lastFedAt;
    if (lastFed == null) return null;
    final end = lastFed.add(_feedCooldown);
    final now = DateTime.now();
    return now.isBefore(end) ? end.difference(now) : null;
  }

  Future<void> _onFoodDropped(FoodType food) async {
    if (_eating || _cooldownRemaining != null) return;
    setState(() => _eating = true);
    HapticFeedback.lightImpact();

    final feedCall = ref.read(petRepositoryProvider).feed(food);
    final minDisplay = Future.delayed(const Duration(milliseconds: 1600));

    try {
      final results = await Future.wait([feedCall, minDisplay]);
      if (!mounted) return;
      setState(() {
        _pet = results[0] as Pet;
        _eating = false;
      });
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => _YumSheet(food: food),
      );
      if (mounted) Navigator.of(context).pop();
    } on FeedCooldownException {
      await minDisplay;
      if (!mounted) return;
      setState(() => _eating = false);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text('Already fed recently — try again later'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final remaining = _cooldownRemaining;

    return GlassScaffold(
      appBar: GlassAppBar(title: _eating ? "They're Eating" : 'Feed'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            children: [
              Text(
                remaining == null
                    ? 'Drag food to your cat'
                    : 'All full for now',
                style: TextStyle(color: t.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SoftCard(
                  padding: EdgeInsets.zero,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: Image.asset(
                            _eating
                                ? 'assets/images/pet/cat_eating.png'
                                : 'assets/images/pet/cat_waiting.png',
                            key: ValueKey(_eating),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stack) => Container(
                              color: t.textPrimary.withValues(alpha: 0.06),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.pets,
                                size: 96,
                                color: t.textSecondary,
                              ),
                            ),
                          ),
                        ),
                        // Drop zone covers the cat itself, separate from the
                        // draggable bowls' row at the bottom — the two must
                        // not overlap, or the only "drop" that registers is
                        // dropping a bowl back where it started. Hidden
                        // entirely during cooldown/eating so there's nothing
                        // to accidentally drop onto.
                        if (remaining == null && !_eating)
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            bottom: 132,
                            child: DragTarget<FoodType>(
                              onWillAcceptWithDetails: (details) {
                                setState(() => _hovering = true);
                                return true;
                              },
                              onLeave: (_) => setState(() => _hovering = false),
                              onAcceptWithDetails: (details) {
                                setState(() => _hovering = false);
                                _onFoodDropped(details.data);
                              },
                              builder: (context, candidate, rejected) =>
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    color: _hovering
                                        ? t.positive.withValues(alpha: 0.12)
                                        : Colors.transparent,
                                  ),
                            ),
                          ),
                        Positioned(
                          bottom: 20,
                          left: 16,
                          right: 16,
                          child: remaining != null
                              ? _CooldownBanner(remaining: remaining)
                              : Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    for (final food in FoodType.values)
                                      _DraggableFoodBowl(
                                        food: food,
                                        enabled: !_eating,
                                      ),
                                  ],
                                ),
                        ),
                      ],
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

class _DraggableFoodBowl extends StatelessWidget {
  final FoodType food;
  final bool enabled;
  const _DraggableFoodBowl({required this.food, required this.enabled});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final bowl = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BowlImage(food: food, size: 52),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '+${food.coinReward}',
            style: TextStyle(
              color: t.positive,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
    if (!enabled) return Opacity(opacity: 0.4, child: bowl);
    return Draggable<FoodType>(
      data: food,
      feedback: Material(
        color: Colors.transparent,
        child: _BowlImage(food: food, size: 60),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: bowl),
      child: bowl,
    );
  }
}

class _BowlImage extends StatelessWidget {
  final FoodType food;
  final double size;
  const _BowlImage({required this.food, required this.size});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        food.bowlAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => Container(
          width: size,
          height: size,
          color: t.textPrimary.withValues(alpha: 0.08),
          alignment: Alignment.center,
          child: Icon(
            Icons.set_meal_outlined,
            size: size * 0.5,
            color: t.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Countdown shown in place of the food row while the feed cooldown from
/// the last meal is still active.
class _CooldownBanner extends StatelessWidget {
  final Duration remaining;
  const _CooldownBanner({required this.remaining});

  String get _label {
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;
    if (hours > 0) return 'Try again in ${hours}h ${minutes}m';
    return 'Try again in ${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final elapsed =
        1 - (remaining.inSeconds / _feedCooldown.inSeconds).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _label,
            style: TextStyle(
              color: t.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: elapsed,
              minHeight: 8,
              backgroundColor: t.textPrimary.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation(t.positive),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reward summary shown as a modal bottom sheet over the eating scene once
/// feeding completes, instead of replacing the whole screen.
class _YumSheet extends StatelessWidget {
  final FoodType food;
  const _YumSheet({required this.food});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: SoftCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Yum!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: t.positive.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '+${food.coinReward} Happiness',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: t.positive,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Hunger',
                style: TextStyle(color: t.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 8),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 1.0, end: 0.0),
                duration: const Duration(milliseconds: 1200),
                curve: Curves.easeOut,
                builder: (context, value, child) => Stack(
                  children: [
                    Container(
                      height: 12,
                      decoration: BoxDecoration(
                        color: t.textPrimary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: value.clamp(0.0, 1.0),
                      child: Container(
                        height: 12,
                        decoration: BoxDecoration(
                          color: t.positive,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              PillButton(
                label: 'Great!',
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
