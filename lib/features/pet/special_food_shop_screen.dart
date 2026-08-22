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
            child: Center(
              child: Text(
                '$_coins coins',
                style: TextStyle(
                  color: t.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: [
              const _SectionLabel(label: 'Your inventory'),
              const SizedBox(height: 8),
              FutureBuilder<List<FoodInventoryItem>>(
                future: _inventoryFuture,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const SkeletonLoader(height: 80);
                  }
                  final items = snapshot.data!;
                  if (items.isEmpty) {
                    return EmptyStateBox(
                      icon: Icons.set_meal_outlined,
                      message: 'No special foods in stock.\nBuy some below!',
                    );
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
              const _SectionLabel(label: 'Buy special foods'),
              const SizedBox(height: 8),
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
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return Text(
      label,
      style: TextStyle(
        color: t.textMuted,
        fontWeight: FontWeight.w700,
        fontSize: 13,
        letterSpacing: 0.5,
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
              color: t.positive.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '+${item.coinReward}',
              style: TextStyle(
                color: t.positive,
                fontWeight: FontWeight.w700,
              ),
            ),
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

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final affordable = coins >= food.coinCost;

    return Opacity(
      opacity: affordable ? 1 : 0.6,
      child: SoftCard(
        padding: const EdgeInsets.all(14),
        child: Row(
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
                  Text(
                    food.name,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    food.description,
                    style: TextStyle(color: t.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${food.usesPerPurchase} uses · ${food.satiationHours}h · +${food.coinReward} coins/use',
                    style: TextStyle(color: t.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            PillButton(
              label: '${food.coinCost}',
              primary: affordable,
              onTap: (busy || !affordable) ? null : onPurchase,
            ),
          ],
        ),
      ),
    );
  }
}
