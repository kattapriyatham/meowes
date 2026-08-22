import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/models/food.dart';
import 'package:meowes_app/models/pet.dart';
import 'package:meowes_app/models/special_food.dart';
import 'package:meowes_app/repositories/pet_repository.dart';

/// Drag payload union so the drop zone accepts both regular foods and
/// purchased special foods. Each carries the data needed to run the feed
/// call and render the reward sheet.
sealed class _FeedChoice {
  const _FeedChoice();
}

class _RegularChoice extends _FeedChoice {
  final FoodType food;
  const _RegularChoice(this.food);
}

class _SpecialChoice extends _FeedChoice {
  final FoodInventoryItem item;
  const _SpecialChoice(this.item);
}

/// Dev/test-only escape hatch: `flutter run --dart-define=FEED_TESTING_UNLIMITED=true`
/// skips the *client-side* cooldown gate below so the drop zone stays live
/// for repeat testing. It can't bypass the server-side check in
/// `feed_pet()` — that RPC enforces the real cooldown regardless, so
/// a `feed()` call against a pet fed within the window still throws
/// [FeedCooldownException] even with this set.
const _bypassFeedCooldown = bool.fromEnvironment('FEED_TESTING_UNLIMITED');

/// Single-screen feeding flow: drag any of the three foods straight onto
/// the cat to feed it — no separate "choose food" or "place food" screens.
/// Eating plays out in place, then a "Yum!" bottom sheet summarizes the
/// reward and the screen pops back. If the cooldown from the last feed is
/// still active, dragging is disabled and a countdown is shown instead.
class FeedFlowScreen extends ConsumerStatefulWidget {
  const FeedFlowScreen({super.key, required this.pet, this.highlightFood});
  final Pet pet;

  /// Set when this screen was opened from a pet-hungry push notification
  /// (see `PetFeedDeepLinkScreen`) — pulses an outline around this food's
  /// bowl so the user can see at a glance which one the notification was
  /// about. Purely visual: the user still has to drag it themselves.
  final FoodType? highlightFood;

  @override
  ConsumerState<FeedFlowScreen> createState() => _FeedFlowScreenState();
}

class _FeedFlowScreenState extends ConsumerState<FeedFlowScreen> {
  late Pet _pet;
  bool _eating = false;
  bool _hovering = false;
  Timer? _ticker;
  late Future<List<FoodInventoryItem>> _inventoryFuture;

  @override
  void initState() {
    super.initState();
    _pet = widget.pet;
    _inventoryFuture = ref.read(petRepositoryProvider).getFoodInventory();
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

  /// Each food cools down independently — feeding fish doesn't touch
  /// treats' or dry food's own clock. Mirrors the per-food cooldown
  /// enforced server-side in `feed_pet()`
  /// (supabase/migrations/20260815160000_independent_food_cooldowns.sql).
  DateTime? _lastFedAtFor(FoodType food) {
    switch (food) {
      case FoodType.fish:
        return _pet.lastFishFedAt;
      case FoodType.treats:
        return _pet.lastTreatsFedAt;
      case FoodType.dryFood:
        return _pet.lastDryFoodFedAt;
    }
  }

  Duration? _remainingFor(FoodType food) {
    if (_bypassFeedCooldown) return null;
    final lastFed = _lastFedAtFor(food);
    if (lastFed == null) return null;
    final end = lastFed.add(food.satiationDuration);
    final now = DateTime.now();
    return now.isBefore(end) ? end.difference(now) : null;
  }

  Duration? _specialRemaining(FoodInventoryItem item) {
    if (_bypassFeedCooldown) return null;
    if (_pet.lastSpecialFoodId == item.specialFoodId && _pet.lastSpecialFedAt != null) {
      final end = _pet.lastSpecialFedAt!.add(item.satiationDuration);
      final now = DateTime.now();
      return now.isBefore(end) ? end.difference(now) : null;
    }
    return null;
  }

  bool get _anyRegularAvailable => FoodType.values.any((f) => _remainingFor(f) == null);

  Future<void> _onRegularDropped(FoodType food) async {
    if (_eating || _remainingFor(food) != null) return;
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

  Future<void> _onSpecialDropped(FoodInventoryItem item) async {
    if (_eating || _specialRemaining(item) != null) return;
    setState(() => _eating = true);
    HapticFeedback.lightImpact();

    final feedCall = ref.read(petRepositoryProvider).feedSpecialFood(item.id);
    final minDisplay = Future.delayed(const Duration(milliseconds: 1600));

    try {
      final results = await Future.wait([feedCall, minDisplay]);
      if (!mounted) return;
      final result = results[0] as FeedSpecialResult;
      setState(() {
        _pet = Pet.fromJson(result.pet);
        _eating = false;
      });
      // Refresh inventory
      _inventoryFuture = ref.read(petRepositoryProvider).getFoodInventory();
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => _YumSheetSpecial(
          foodName: result.food.name,
          coinReward: result.food.coinReward,
          usesRemaining: result.usesRemaining,
        ),
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

    return GlassScaffold(
      appBar: GlassAppBar(title: _eating ? "They're Eating" : 'Feed'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            children: [
              FutureBuilder<List<FoodInventoryItem>>(
                future: _inventoryFuture,
                builder: (context, snapshot) {
                  final specialItems = snapshot.data ?? <FoodInventoryItem>[];
                  final anyAvailable = _anyRegularAvailable ||
                      specialItems.any((i) => _specialRemaining(i) == null);
                  return Text(
                    anyAvailable ? 'Drag food to your cat' : 'All full for now',
                    style: TextStyle(color: t.textSecondary, fontSize: 14),
                  );
                },
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
                        Image.asset('assets/bg-1.png', fit: BoxFit.cover),
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
                        // dropping a bowl back where it started. Hidden while
                        // eating, or once every food is on cooldown (nothing
                        // left to drag — a locked bowl already blocks its
                        // own drag via _DraggableFoodBowl's `enabled` flag).
                        FutureBuilder<List<FoodInventoryItem>>(
                          future: _inventoryFuture,
                          builder: (context, snapshot) {
                            final specialItems = snapshot.data ?? <FoodInventoryItem>[];
                            final anyAvailable = _anyRegularAvailable ||
                                specialItems.any((i) => _specialRemaining(i) == null);
                            if (!anyAvailable || _eating) return const SizedBox();
                            return Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              bottom: 132,
                              child: DragTarget<_FeedChoice>(
                                onWillAcceptWithDetails: (details) {
                                  setState(() => _hovering = true);
                                  return true;
                                },
                                onLeave: (_) => setState(() => _hovering = false),
                                onAcceptWithDetails: (details) {
                                  setState(() => _hovering = false);
                                  if (details.data is _RegularChoice) {
                                    _onRegularDropped((details.data as _RegularChoice).food);
                                  } else if (details.data is _SpecialChoice) {
                                    _onSpecialDropped((details.data as _SpecialChoice).item);
                                  }
                                },
                                builder: (context, candidate, rejected) =>
                                    AnimatedContainer(
                                      duration: const Duration(milliseconds: 150),
                                      color: _hovering
                                          ? t.positive.withValues(alpha: 0.12)
                                          : Colors.transparent,
                                    ),
                              ),
                            );
                          },
                        ),
                        Positioned(
                          bottom: 20,
                          left: 16,
                          right: 16,
                          child: FutureBuilder<List<FoodInventoryItem>>(
                            future: _inventoryFuture,
                            builder: (context, snapshot) {
                              final specialItems = snapshot.data ?? <FoodInventoryItem>[];
                              final specialBowls = specialItems
                                  .where((i) => _specialRemaining(i) == null)
                                  .map((i) => _DraggableSpecialBowl(
                                        item: i,
                                        enabled: !_eating && _specialRemaining(i) == null,
                                        remaining: _specialRemaining(i),
                                      ))
                                  .toList();
                              final regularBowls = FoodType.values
                                  .where((f) => _remainingFor(f) == null)
                                  .map((f) => _DraggableFoodBowl(
                                        food: f,
                                        enabled: !_eating && _remainingFor(f) == null,
                                        remaining: _remainingFor(f),
                                        highlighted: f == widget.highlightFood,
                                      ))
                                  .toList();

                              // Show regular first, then specials
                              final allBowls = [...regularBowls, ...specialBowls];
                              if (allBowls.isEmpty) return const SizedBox();

                              return Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: allBowls,
                              );
                            },
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

/// Reward sheet for special foods.
class _YumSheetSpecial extends StatelessWidget {
  final String foodName;
  final int coinReward;
  final int usesRemaining;

  const _YumSheetSpecial({
    required this.foodName,
    required this.coinReward,
    required this.usesRemaining,
  });

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
                  '+$coinReward Happiness',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: t.positive,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '$foodName · $usesRemaining uses left',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textSecondary, fontSize: 14),
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

class _DraggableFoodBowl extends StatelessWidget {
  final FoodType food;
  final bool enabled;

  /// Time left until this specific food is available again, or null when
  /// it can be fed now — each food cools down independently, so this
  /// differs per bowl. Shown as a countdown chip in place of the
  /// coin-reward badge while on cooldown.
  final Duration? remaining;

  /// True when a pet-hungry push notification named this food — draws a
  /// pulsing highlight around its bowl (see [_PulsingHighlight]).
  final bool highlighted;

  const _DraggableFoodBowl({
    required this.food,
    required this.enabled,
    this.remaining,
    this.highlighted = false,
  });

  String get _timerLabel {
    final r = remaining!;
    final hours = r.inHours;
    final minutes = r.inMinutes % 60;
    return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final onCooldown = remaining != null;
    final bowlImage = _BowlImage(food: food, size: 52);
    final bowl = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        highlighted ? _PulsingHighlight(child: bowlImage) : bowlImage,
        const SizedBox(height: 4),
        Text(
          food.label,
          style: TextStyle(
            color: t.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(10),
          ),
          child: onCooldown
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer_outlined, size: 11, color: t.textSecondary),
                    const SizedBox(width: 3),
                    Text(
                      _timerLabel,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                )
              : Text(
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
    return Draggable<_FeedChoice>(
      data: _RegularChoice(food),
      feedback: Material(
        color: Colors.transparent,
        child: _BowlImage(food: food, size: 60),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: bowl),
      child: bowl,
    );
  }
}

/// Wraps a bowl image with a slow, repeating glow ring — draws attention
/// to the food a tapped pet-hungry notification named. Purely visual: it
/// doesn't drag or feed anything on the user's behalf.
class _PulsingHighlight extends StatefulWidget {
  final Widget child;
  const _PulsingHighlight({required this.child});

  @override
  State<_PulsingHighlight> createState() => _PulsingHighlightState();
}

class _PulsingHighlightState extends State<_PulsingHighlight> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: t.positive.withValues(alpha: 0.25 + _controller.value * 0.35),
              blurRadius: 8 + _controller.value * 6,
              spreadRadius: 1 + _controller.value * 2,
            ),
          ],
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// Draggable bowl for special food inventory items.
class _DraggableSpecialBowl extends StatelessWidget {
  final FoodInventoryItem item;
  final bool enabled;
  final Duration? remaining;

  const _DraggableSpecialBowl({
    required this.item,
    required this.enabled,
    this.remaining,
  });

  String get _timerLabel {
    final r = remaining!;
    final hours = r.inHours;
    final minutes = r.inMinutes % 60;
    return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final onCooldown = remaining != null;
    final bowl = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BowlImageSpecial(item: item, size: 52),
        const SizedBox(height: 4),
        Text(
          item.name,
          style: TextStyle(
            color: t.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(10),
          ),
          child: onCooldown
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer_outlined, size: 11, color: t.textSecondary),
                    const SizedBox(width: 3),
                    Text(
                      _timerLabel,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '+${item.coinReward}',
                      style: TextStyle(
                        color: t.positive,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${item.usesRemaining} left',
                      style: TextStyle(
                        color: t.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
    if (!enabled) return Opacity(opacity: 0.4, child: bowl);
    return Draggable<_FeedChoice>(
      data: _SpecialChoice(item),
      feedback: Material(
        color: Colors.transparent,
        child: _BowlImageSpecial(item: item, size: 60),
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

class _BowlImageSpecial extends StatelessWidget {
  final FoodInventoryItem item;
  final double size;
  const _BowlImageSpecial({required this.item, required this.size});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        item.bowlAsset,
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