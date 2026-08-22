// lib/features/pet/special_food_shop_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/models/pet.dart';
import 'package:meowes_app/models/special_food.dart';
import 'package:meowes_app/repositories/pet_repository.dart';

/// Shop and inventory for purchasable special foods: a one-time coin
/// purchase adds a limited-use food item, which the feed flow can then
/// consume one use at a time. Split into two sections — buyable catalog
/// on top, owned inventory with remaining uses below.
class SpecialFoodShopScreen extends ConsumerStatefulWidget {
  const SpecialFoodShopScreen({super.key});

  @override
  ConsumerState<SpecialFoodShopScreen> createState() =>
      _SpecialFoodShopScreenState();
}

class _SpecialFoodShopScreenState extends ConsumerState<SpecialFoodShopScreen> {
  late Future<List<SpecialFood>> _catalogFuture;
  late Future<List<FoodInventoryItem>> _inventoryFuture;
  int _coins = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _catalogFuture = ref.read(petRepositoryProvider).getSpecialFoods();
    _inventoryFuture = ref.read(petRepositoryProvider).getFoodInventory();
    _loadCoins();
  }

  Future<void> _loadCoins() async {
    final pet = await ref.read(petRepositoryProvider).getOrCreatePet();
    if (mounted) setState(() => _coins = pet.coins);
  }

  Future<void> _refresh() async {
    setState(() {
      _catalogFuture = ref.read(petRepositoryProvider).getSpecialFoods();
      _inventoryFuture = ref.read(petRepositoryProvider).getFoodInventory();
    });
    await _loadCoins();
  }

  Future<void> _purchase(SpecialFood food) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(petRepositoryProvider).purchaseSpecialFood(food.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text('Bought ${food.name} · ${food.usesPerPurchase} uses'),
          ),
        );
      await _refresh();
    } on InsufficientCoinsException {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('Not enough coins')),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return GlassScaffold(
      appBar: GlassAppBar(
        title: 'Special Foods',
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(child: _CoinBalancePill(amount: _coins)),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
            children: [
              Text(
                'Treat your cat with something extra special!',
                style: TextStyle(color: t.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 20),
              const _SectionLabel(icon: Icons.shopping_bag_outlined, label: 'Your Inventory'),
              const SizedBox(height: 10),
              FutureBuilder<List<FoodInventoryItem>>(
                future: _inventoryFuture,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const SkeletonLoader(height: 80);
                  }
                  final items = snapshot.data!;
                  if (items.isEmpty) {
                    return const _EmptyInventoryCard();
                  }
                  return Column(
                    children: [
                      for (final item in items) ...[
                        _InventoryCard(item: item),
                        const SizedBox(height: 10),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              const _SectionLabel(icon: Icons.shopping_bag_outlined, label: 'Buy Special Foods'),
              const SizedBox(height: 10),
              FutureBuilder<List<SpecialFood>>(
                future: _catalogFuture,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SkeletonLoader(height: 200);
                  final foods = snapshot.data!;
                  return Column(
                    children: [
                      for (final food in foods) ...[
                        _CatalogCard(
                          food: food,
                          coins: _coins,
                          busy: _busy,
                          onPurchase: () => _purchase(food),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              const _HappinessBanner(),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoinBalancePill extends StatelessWidget {
  final int amount;
  const _CoinBalancePill({required this.amount});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: t.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.textPrimary.withValues(alpha: 0.08)),
      ),
      child: CoinAmount(amount: amount, iconSize: 18),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return Row(
      children: [
        Icon(icon, size: 18, color: t.positive),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ],
    );
  }
}

/// Illustrated empty state for the inventory section — richer than the
/// generic [EmptyStateBox] since this screen has a specific mockup for it.
class _EmptyInventoryCard extends StatelessWidget {
  const _EmptyInventoryCard();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: t.textPrimary.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.pets, size: 13, color: t.textMuted.withValues(alpha: 0.5)),
                    const SizedBox(width: 8),
                    Icon(Icons.set_meal_outlined, size: 26, color: t.textMuted),
                    const SizedBox(width: 8),
                    Icon(Icons.pets, size: 13, color: t.textMuted.withValues(alpha: 0.5)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'No special foods in stock.',
                  style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Buy some below!',
                  style: TextStyle(color: t.textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  'assets/images/pet/cat_content.png',
                  width: 84,
                  height: 84,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(width: 84, height: 84),
                ),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: t.cardColor, shape: BoxShape.circle),
                  child: Icon(Icons.favorite, size: 14, color: t.positive),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InventoryCard extends StatelessWidget {
  final FoodInventoryItem item;
  const _InventoryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return SoftCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              item.bowlAsset,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 48,
                height: 48,
                color: t.textPrimary.withValues(alpha: 0.08),
                alignment: Alignment.center,
                child: Icon(Icons.set_meal_outlined, color: t.textSecondary),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.usesRemaining} uses left · ${item.satiationHours}h satiation',
                  style: TextStyle(color: t.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: CoinAmount.gold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: CoinAmount(amount: item.coinReward, showSign: true),
          ),
        ],
      ),
    );
  }
}

class _CatalogCard extends StatelessWidget {
  final SpecialFood food;
  final int coins;
  final bool busy;
  final VoidCallback onPurchase;

  const _CatalogCard({
    required this.food,
    required this.coins,
    required this.busy,
    required this.onPurchase,
  });

  /// Only one item is flagged "Popular" — there's no popularity-tracking
  /// data yet, so this is a simple key match rather than a new schema
  /// column for a single decorative tag.
  bool get _isPopular => food.key == 'premium_fish';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final affordable = coins >= food.coinCost;

    return Opacity(
      opacity: affordable ? 1 : 0.6,
      child: SoftCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                food.bowlAsset,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 56,
                  height: 56,
                  color: t.textPrimary.withValues(alpha: 0.08),
                  alignment: Alignment.center,
                  child: Icon(Icons.set_meal_outlined, color: t.textSecondary),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          food.name,
                          style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_isPopular) ...[
                        const SizedBox(width: 6),
                        const _PopularBadge(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    food.description,
                    style: TextStyle(color: t.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 10,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _StatChip(icon: Icons.pets, text: '${food.usesPerPurchase} uses'),
                      _StatChip(icon: Icons.access_time, text: '${food.satiationHours}h'),
                      _StatChip(
                        icon: Icons.pets,
                        text: '+${food.coinReward} coins/use',
                        color: t.positive,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _PriceCircle(
              cost: food.coinCost,
              affordable: affordable,
              onTap: (busy || !affordable) ? null : onPurchase,
            ),
          ],
        ),
      ),
    );
  }
}

class _PopularBadge extends StatelessWidget {
  const _PopularBadge();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: t.positiveTint,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star, size: 11, color: t.positive),
          const SizedBox(width: 3),
          Text(
            'Popular',
            style: TextStyle(color: t.positive, fontWeight: FontWeight.w700, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const _StatChip({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final c = color ?? t.textMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: c),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
            color: c,
            fontSize: 11,
            fontWeight: color != null ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

/// Fixed-diameter circular price badge for a catalog card — PillButton
/// sizes itself to its label's text width, which reads as a narrow oval
/// rather than a circle for a short number like a coin cost. FittedBox
/// shrinks 3-digit costs to still fit the same diameter.
class _PriceCircle extends StatelessWidget {
  final int cost;
  final bool affordable;
  final VoidCallback? onTap;

  const _PriceCircle({
    required this.cost,
    required this.affordable,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final bg = affordable ? t.positiveTint : t.textPrimary.withValues(alpha: 0.08);
    final fg = affordable ? t.positive : t.textSecondary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              child: Text(
                '$cost',
                style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            const SizedBox(height: 1),
            Icon(Icons.pets, size: 10, color: fg),
          ],
        ),
      ),
    );
  }
}

class _HappinessBanner extends StatelessWidget {
  const _HappinessBanner();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.positiveTint,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, color: t.positive, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Special foods = Extra happiness!',
                  style: TextStyle(color: t.positive, fontWeight: FontWeight.w800, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  "Use them to boost your cat's mood and earn more rewards.",
                  style: TextStyle(color: t.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              'assets/images/pet/cat_petting.png',
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox(width: 64, height: 64),
            ),
          ),
        ],
      ),
    );
  }
}
