enum SplitType { equal, percentage, exact }

class SplitCalculator {
  /// All amounts are in minor currency units (e.g. paise) as ints, to avoid
  /// floating point rounding errors. Returns a map of participantId -> share.
  static Map<String, int> calculate({
    required int totalMinorUnits,
    required SplitType type,
    required List<String> participantIds,
    Map<String, double>? percentages,
    Map<String, int>? exactAmounts,
  }) {
    switch (type) {
      case SplitType.equal:
        return _splitEqual(totalMinorUnits, participantIds);
      case SplitType.percentage:
        return _splitPercentage(totalMinorUnits, participantIds, percentages);
      case SplitType.exact:
        return _splitExact(totalMinorUnits, participantIds, exactAmounts);
    }
  }

  static Map<String, int> _splitEqual(int total, List<String> ids) {
    final base = total ~/ ids.length;
    final remainder = total % ids.length;
    return {
      for (var i = 0; i < ids.length; i++)
        ids[i]: base + (i < remainder ? 1 : 0),
    };
  }

  static Map<String, int> _splitPercentage(
    int total,
    List<String> ids,
    Map<String, double>? percentages,
  ) {
    if (percentages == null || percentages.length != ids.length) {
      throw ArgumentError('percentages must be provided for every participant');
    }
    final sum = percentages.values.fold<double>(0, (a, b) => a + b);
    if ((sum - 100).abs() > 0.01) {
      throw ArgumentError('percentages must sum to 100, got $sum');
    }
    final result = <String, int>{};
    var allocated = 0;
    for (var i = 0; i < ids.length; i++) {
      final id = ids[i];
      if (i == ids.length - 1) {
        result[id] = total - allocated; // last participant absorbs rounding
      } else {
        final share = (total * (percentages[id]! / 100)).round();
        result[id] = share;
        allocated += share;
      }
    }
    return result;
  }

  static Map<String, int> _splitExact(
    int total,
    List<String> ids,
    Map<String, int>? exactAmounts,
  ) {
    if (exactAmounts == null || exactAmounts.length != ids.length) {
      throw ArgumentError('exactAmounts must be provided for every participant');
    }
    final sum = exactAmounts.values.fold<int>(0, (a, b) => a + b);
    if (sum != total) {
      throw ArgumentError('exact amounts must sum to $total, got $sum');
    }
    return Map<String, int>.from(exactAmounts);
  }
}
