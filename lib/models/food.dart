enum FoodType { fish, treats, dryFood }

extension FoodTypeInfo on FoodType {
  String get key {
    switch (this) {
      case FoodType.fish:
        return 'fish';
      case FoodType.treats:
        return 'treats';
      case FoodType.dryFood:
        return 'dry_food';
    }
  }

  String get label {
    switch (this) {
      case FoodType.fish:
        return 'Fish';
      case FoodType.treats:
        return 'Treats';
      case FoodType.dryFood:
        return 'Dry Food';
    }
  }

  /// How long this food keeps the cat full before it's hungry again —
  /// mirrors `food_satiation_hours()` in
  /// supabase/migrations/20260815110000_food_satiation_and_hunger_decay.sql,
  /// which also drives the feed cooldown server-side.
  Duration get satiationDuration {
    switch (this) {
      case FoodType.fish:
        return const Duration(hours: 6);
      case FoodType.dryFood:
        return const Duration(hours: 4);
      case FoodType.treats:
        return const Duration(hours: 12);
    }
  }

  int get coinReward {
    switch (this) {
      case FoodType.fish:
        return 3;
      case FoodType.treats:
        return 2;
      case FoodType.dryFood:
        return 2;
    }
  }

  String get bowlAsset {
    switch (this) {
      case FoodType.fish:
        return 'assets/images/pet/bowl_fish.png';
      case FoodType.treats:
        return 'assets/images/pet/bowl_treats.png';
      case FoodType.dryFood:
        return 'assets/images/pet/bowl_dry_food.png';
    }
  }
}

/// Inverse of [FoodTypeInfo.key] — used to route a push notification's
/// `food_key` data field back to a [FoodType] (see
/// `PetFeedDeepLinkScreen`). Returns null for an unrecognized or missing
/// key rather than throwing, since it's fed untrusted push-payload data.
FoodType? foodTypeFromKey(String? key) {
  for (final food in FoodType.values) {
    if (food.key == key) return food;
  }
  return null;
}
