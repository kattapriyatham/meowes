enum ActivityKind { expense, settlement, petActivity }

ActivityKind _kindFromDb(String db) {
  switch (db) {
    case 'expense':
      return ActivityKind.expense;
    case 'settlement':
      return ActivityKind.settlement;
    case 'pet_activity':
      return ActivityKind.petActivity;
    default:
      throw ArgumentError('unknown activity kind: $db');
  }
}

/// One row in the signed-in user's unified activity feed (expenses,
/// settlements, pet-coin spending), from `get_my_activity_feed()`.
class ActivityItem {
  final ActivityKind kind;
  final String refId;

  /// Expense description or pet activity name. Null for settlements —
  /// those are rendered from [counterpartId] instead ("You paid X" /
  /// "X paid you").
  final String? title;

  /// The expense's payer, or the other party to a settlement. Null for
  /// pet activities, which have no second person involved.
  final String? counterpartId;

  /// True when the signed-in user is the one who paid — the expense's
  /// payer, or the settlement's `from_user`. [counterpartId] alone can't
  /// distinguish "you paid them" from "they paid you", since it always
  /// holds "whichever side isn't me". Null for pet activities.
  final bool? isMine;

  final double amount;
  final DateTime occurredAt;

  ActivityItem({
    required this.kind,
    required this.refId,
    this.title,
    this.counterpartId,
    this.isMine,
    required this.amount,
    required this.occurredAt,
  });

  factory ActivityItem.fromJson(Map<String, dynamic> json) {
    final rawAmount = json['amount'];
    final amount = rawAmount is num ? rawAmount.toDouble() : double.parse(rawAmount.toString());
    return ActivityItem(
      kind: _kindFromDb(json['kind'] as String),
      refId: json['ref_id'] as String,
      title: json['title'] as String?,
      counterpartId: json['counterpart_id'] as String?,
      isMine: json['is_mine'] as bool?,
      amount: amount,
      occurredAt: DateTime.parse(json['occurred_at'] as String),
    );
  }
}
