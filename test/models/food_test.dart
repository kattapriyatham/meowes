import 'package:flutter_test/flutter_test.dart';
import 'package:meowes_app/models/food.dart';

void main() {
  group('foodTypeFromKey', () {
    test('parses each valid key back to its FoodType', () {
      expect(foodTypeFromKey('fish'), FoodType.fish);
      expect(foodTypeFromKey('treats'), FoodType.treats);
      expect(foodTypeFromKey('dry_food'), FoodType.dryFood);
    });

    test('returns null for an unknown or missing key', () {
      expect(foodTypeFromKey('not_a_food'), isNull);
      expect(foodTypeFromKey(null), isNull);
    });
  });
}
