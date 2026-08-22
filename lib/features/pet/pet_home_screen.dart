import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/pet/activities_screen.dart';
import 'package:meowes_app/features/pet/feed_flow_screen.dart';
import 'package:meowes_app/features/pet/memory_journal_screen.dart';
import 'package:meowes_app/features/pet/pet_interaction_screen.dart';
import 'package:meowes_app/features/pet/special_food_shop_screen.dart';
import 'package:meowes_app/models/pet.dart';
import 'package:meowes_app/repositories/pet_repository.dart';

/// Fill behind the cat banner, matching the app's own cream background.
const _bannerGreen = Color(0xFFF3EBDC);

/// Width/height ratio of assets/images/pet/cat_idle_cropped.png (874x965),
/// used to size its display box without distortion.
const _catAspect = 874 / 965;

/// Dedicated pet hub: mood-aware cat, entry points into the dedicated Pet
/// and Feed interaction screens, coin balance, and links to the Activities
/// shop and the Memory journal. Reached by tapping the cat mascot on Home,
/// or the Pet tab in the bottom dock.
class PetHomeScreen extends ConsumerStatefulWidget {
  const PetHomeScreen({super.key});

  @override
  ConsumerState<PetHomeScreen> createState() => _PetHomeScreenState();
}

class _PetHomeScreenState extends ConsumerState<PetHomeScreen> {
  Pet? _pet;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pet = await ref.read(petRepositoryProvider).getOrCreatePet();
    if (mounted) setState(() => _pet = pet);
  }

  Future<void> _openPetScreen() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PetInteractionScreen()));
    _load();
  }

  Future<void> _openFeedFlow() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => FeedFlowScreen(pet: _pet!)));
    _load();
  }

  IconData _moodIcon(MoodState mood) {
    switch (mood) {
      case MoodState.sad:
        return Icons.sentiment_very_dissatisfied;
      case MoodState.content:
        return Icons.sentiment_neutral;
      case MoodState.happy:
        return Icons.sentiment_satisfied;
      case MoodState.ecstatic:
        return Icons.sentiment_very_satisfied;
    }
  }

  String _moodLabel(MoodState mood) {
    switch (mood) {
      case MoodState.sad:
        return 'Sad';
      case MoodState.content:
        return 'Content';
      case MoodState.happy:
        return 'Happy';
      case MoodState.ecstatic:
        return 'Ecstatic';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final pet = _pet;

    return GlassScaffold(
      // Title is rendered as a large centered heading below (matching the
      // reference design) rather than through GlassAppBar's left-aligned
      // style, which every other screen still uses — so only the leading
      // back button comes from the shared app bar here.
      appBar: const GlassAppBar(),
      body: pet == null
          ? const SafeArea(
              child: Center(
                child: SkeletonLoader(height: 200, width: 200, radius: 100),
              ),
            )
          // top: false — the green banner below paints edge-to-edge behind
          // the status bar itself; it adds its own top inset internally
          // instead of leaving a cream strip above it.
          : SafeArea(
              top: false,
              child: ListView(
                // No horizontal padding here — the cat banner below needs to
                // reach the screen edges. Every other item supplies its own
                // 20px horizontal inset instead (Padding wrapper per item).
                padding: const EdgeInsets.only(top: 0, bottom: 100),
                children: [
                  // Same fill as the cat scene below and flush against it
                  // (no gap), so the two read as one continuous area that
                  // starts right at the top of the screen.
                  Container(
                    width: double.infinity,
                    color: _bannerGreen,
                    padding: EdgeInsets.fromLTRB(
                      16,
                      MediaQuery.of(context).padding.top + 12,
                      16,
                      16,
                    ),
                    child: Center(
                      child: Text(
                        pet.name,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 30,
                        ),
                      ),
                    ),
                  ),
                  // Full-bleed banner, no horizontal inset — reaches the
                  // screen edges with no rounded corners. Background is a
                  // solid fill matching the title block above, with a soft
                  // fade at the top so the leaf art doesn't cut off
                  // abruptly. Paint order (back to front): fill, leaf art,
                  // edge fade, sparkles, pills, the Pet/Feed panel, then
                  // the cat photo + heart badge on top — the cat
                  // overlapping the panel is what makes the paws read as
                  // resting on it, rather than being clipped by it.
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AspectRatio(
                        aspectRatio: 0.9,
                        child: Container(
                          color: _bannerGreen,
                          child: Image.asset(
                            'assets/pet-bg.png',
                            fit: BoxFit.fill,
                            width: double.infinity,
                            height: double.infinity,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 40,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  _bannerGreen,
                                  _bannerGreen.withValues(alpha: 0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Small sparkle accents scattered around the cat.
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Stack(
                            children: const [
                              Align(
                                alignment: Alignment(-0.72, -0.12),
                                child: _Sparkle(size: 14),
                              ),
                              Align(
                                alignment: Alignment(0.8, -0.32),
                                child: _Sparkle(size: 12),
                              ),
                              Align(
                                alignment: Alignment(-0.58, 0.2),
                                child: _Sparkle(size: 10),
                              ),
                              Align(
                                alignment: Alignment(0.7, 0.05),
                                child: _Sparkle(size: 16),
                              ),
                              Align(
                                alignment: Alignment(-0.82, 0.42),
                                child: _Sparkle(size: 10),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Mood/coin pills float over the banner itself instead
                      // of a separate card above it.
                      Positioned(
                        top: 16,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _StatPill(
                                icon: _moodIcon(pet.mood),
                                label: _moodLabel(pet.mood),
                              ),
                              const SizedBox(width: 10),
                              _StatPill(
                                icon: Icons.pets,
                                label: '${pet.coins} coins',
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Narrower inset than the Activities/Memories cards
                      // below, so the panel reads wider/closer to the
                      // screen edges. Sits behind the cat photo (painted
                      // next) so the paws overlap it rather than being
                      // covered by it.
                      Positioned(
                        left: 4,
                        right: 4,
                        bottom: 12,
                        child: _PetFeedPanel(
                          onPet: _openPetScreen,
                          onFeed: _openFeedFlow,
                        ),
                      ),
                      // Cat cutout (pre-cropped to its content bounding box
                      // so the paws sit flush against the bottom of this
                      // box) painted directly on the green — no card/clip,
                      // so it reads as a photo cutout rather than a photo
                      // tile. Lifted off the very bottom edge (rather than
                      // filling it) so only the paws graze the panel's top
                      // instead of the torso covering its labels, and sized
                      // down a little so the ears clear the mood/coin pills.
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 100,
                        child: FractionallySizedBox(
                          widthFactor: 0.62,
                          child: AspectRatio(
                            aspectRatio: _catAspect,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Image.asset(
                                  'assets/images/pet/cat_idle_cropped.png',
                                  fit: BoxFit.contain,
                                  alignment: Alignment.bottomCenter,
                                  width: double.infinity,
                                  height: double.infinity,
                                  errorBuilder: (context, error, stack) => Icon(
                                    Icons.pets,
                                    size: 64,
                                    color: t.textSecondary,
                                  ),
                                ),
                                Positioned(
                                  top: 28,
                                  right: 2,
                                  child: Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.85,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      Icons.favorite_border,
                                      size: 14,
                                      color: t.positive,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SoftCard(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ActivitiesScreen(),
                        ),
                      ),
                      child: Row(
                        children: [
                          _IconChip(icon: Icons.storefront_outlined),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Activities',
                                  style: TextStyle(
                                    color: t.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Spend coins on time with your cat',
                                  style: TextStyle(
                                    color: t.textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, color: t.textMuted),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SoftCard(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SpecialFoodShopScreen(),
                        ),
                      ),
                      child: Row(
                        children: [
                          _IconChip(icon: Icons.set_meal_outlined),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Special Foods',
                                  style: TextStyle(
                                    color: t.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Buy premium food with limited uses',
                                  style: TextStyle(
                                    color: t.textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, color: t.textMuted),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SoftCard(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MemoryJournalScreen(),
                        ),
                      ),
                      child: Row(
                        children: [
                          _IconChip(icon: Icons.menu_book_outlined),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Memories',
                                  style: TextStyle(
                                    color: t.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Your journal of moments together',
                                  style: TextStyle(
                                    color: t.textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, color: t.textMuted),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: t.textSecondary),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: t.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }
}

/// Dark rounded-square icon badge used on the Activities/Memories rows.
class _IconChip extends StatelessWidget {
  final IconData icon;
  const _IconChip({required this.icon});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: t.textPrimary,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 20, color: t.onBrand),
    );
  }
}

/// Small 4-point sparkle accent scattered around the cat banner.
class _Sparkle extends StatelessWidget {
  final double size;
  const _Sparkle({required this.size});

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.auto_awesome,
      size: size,
      color: Colors.white.withValues(alpha: 0.8),
    );
  }
}

/// Single shared panel for Pet/Feed, split into two equal columns — a warm
/// beige card that floats overlapping the bottom edge of the cat photo.
class _PetFeedPanel extends StatelessWidget {
  final VoidCallback onPet;
  final VoidCallback onFeed;
  const _PetFeedPanel({required this.onPet, required this.onFeed});

  /// Olive accent behind the paw icon.
  static const _petAccent = Color(0xFF6E8B4F);

  /// Warm taupe accent behind the bowl icon.
  static const _feedAccent = Color(0xFFA6968A);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF1ECE1), // warm beige panel
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: t.cardShadow,
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: _PetFeedAction(
                icon: Icons.pets,
                accent: _petAccent,
                label: 'Pet',
                subtitle: 'Show some love',
                onTap: onPet,
              ),
            ),
            Expanded(
              child: _PetFeedAction(
                icon: Icons.rice_bowl,
                accent: _feedAccent,
                label: 'Feed',
                subtitle: 'Keep them happy',
                onTap: onFeed,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PetFeedAction extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  const _PetFeedAction({
    required this.icon,
    required this.accent,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 28, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 23,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.textSecondary, fontSize: 15),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 18, color: t.textSecondary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
