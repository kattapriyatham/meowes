import 'package:flutter_test/flutter_test.dart';
import 'package:meowes_app/splitting/split_calculator.dart';

void main() {
  group('SplitCalculator.calculate', () {
    test('equal split distributes remainder cents to first participants', () {
      final result = SplitCalculator.calculate(
        totalMinorUnits: 1001, // e.g. ₹10.01
        type: SplitType.equal,
        participantIds: ['a', 'b', 'c'],
      );
      // 1001 / 3 = 333 remainder 2 -> a and b get 334, c gets 333
      expect(result, {'a': 334, 'b': 334, 'c': 333});
      expect(result.values.reduce((x, y) => x + y), 1001);
    });

    test('percentage split resolves to minor units summing to total', () {
      final result = SplitCalculator.calculate(
        totalMinorUnits: 10000,
        type: SplitType.percentage,
        participantIds: ['a', 'b'],
        percentages: {'a': 30, 'b': 70},
      );
      expect(result, {'a': 3000, 'b': 7000});
    });

    test('percentage split throws if percentages do not sum to 100', () {
      expect(
        () => SplitCalculator.calculate(
          totalMinorUnits: 10000,
          type: SplitType.percentage,
          participantIds: ['a', 'b'],
          percentages: {'a': 30, 'b': 60},
        ),
        throwsArgumentError,
      );
    });

    test('exact split throws if amounts do not sum to total', () {
      expect(
        () => SplitCalculator.calculate(
          totalMinorUnits: 10000,
          type: SplitType.exact,
          participantIds: ['a', 'b'],
          exactAmounts: {'a': 4000, 'b': 5000},
        ),
        throwsArgumentError,
      );
    });

    test('exact split passes through when amounts sum correctly', () {
      final result = SplitCalculator.calculate(
        totalMinorUnits: 10000,
        type: SplitType.exact,
        participantIds: ['a', 'b'],
        exactAmounts: {'a': 4000, 'b': 6000},
      );
      expect(result, {'a': 4000, 'b': 6000});
    });
  });
}
