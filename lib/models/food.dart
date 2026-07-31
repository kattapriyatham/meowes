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
