class SpecialFood {
  final String id;
  final String key;
  final String name;
  final int coinCost;
  final int usesPerPurchase;
  final int satiationHours;
  final int coinReward;
  final String bowlAsset;
  final String description;

  const SpecialFood({
    required this.id,
    required this.key,
    required this.name,
    required this.coinCost,
    required this.usesPerPurchase,
    required this.satiationHours,
    required this.coinReward,
    required this.bowlAsset,
    required this.description,
  });

  factory SpecialFood.fromJson(Map<String, dynamic> json) => SpecialFood(
        id: json['id'] as String,
        key: json['key'] as String,
        name: json['name'] as String,
        coinCost: json['coin_cost'] as int,
        usesPerPurchase: json['uses_per_purchase'] as int,
        satiationHours: json['satiation_hours'] as int,
        coinReward: json['coin_reward'] as int,
        bowlAsset: json['bowl_asset'] as String,
        description: json['description'] as String,
      );
}

class FoodInventoryItem {
  final String id;
  final String specialFoodId;
  final String key;
  final String name;
  final int usesRemaining;
  final int satiationHours;
  final int coinReward;
  final String bowlAsset;
  final DateTime? lastUsedAt;

  const FoodInventoryItem({
    required this.id,
    required this.specialFoodId,
    required this.key,
    required this.name,
    required this.usesRemaining,
    required this.satiationHours,
    required this.coinReward,
    required this.bowlAsset,
    this.lastUsedAt,
  });

  Duration get satiationDuration => Duration(hours: satiationHours);

  factory FoodInventoryItem.fromJson(Map<String, dynamic> json) => FoodInventoryItem(
        id: json['id'] as String,
        specialFoodId: json['special_food_id'] as String,
        key: json['key'] as String,
        name: json['name'] as String,
        usesRemaining: json['uses_remaining'] as int,
        satiationHours: json['satiation_hours'] as int,
        coinReward: json['coin_reward'] as int,
        bowlAsset: json['bowl_asset'] as String,
        lastUsedAt: json['last_used_at'] == null
            ? null
            : DateTime.parse(json['last_used_at'] as String),
      );
}

class FeedSpecialResult {
  final Map<String, dynamic> pet;
  final int usesRemaining;
  final SpecialFood food;

  const FeedSpecialResult({
    required this.pet,
    required this.usesRemaining,
    required this.food,
  });

  factory FeedSpecialResult.fromJson(Map<String, dynamic> json) => FeedSpecialResult(
        pet: json['pet'] as Map<String, dynamic>,
        usesRemaining: json['uses_remaining'] as int,
        food: SpecialFood.fromJson(json['food'] as Map<String, dynamic>),
      );
}
