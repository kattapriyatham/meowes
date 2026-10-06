enum FriendActivityKind { expense, group, settlement }

/// One row in a friend's activity list. [net] follows get_friend_balance's
/// sign convention: net > 0 means the friend owes the signed-in user,
/// net < 0 means the signed-in user owes the friend.
class FriendActivityItem {
  final FriendActivityKind kind;
  final String refId;
  final String name;
  final double net;
  final DateTime date;

  /// When the row was added (expense created, payment confirmed, or latest
  /// event in a group). Null if the backend predates the column.
  final DateTime? addedAt;

  /// True = signed-in user paid, false = the friend paid, null = no single
  /// payer (aggregated group rows).
  final bool? paidByMe;

  FriendActivityItem({
    required this.kind,
    required this.refId,
    required this.name,
    required this.net,
    required this.date,
    this.addedAt,
    this.paidByMe,
  });

  /// Ordering key: the exact add time, falling back to the day-only [date]
  /// when the backend didn't send one.
  DateTime get sortTime => addedAt ?? date;

  factory FriendActivityItem.fromJson(Map<String, dynamic> json) {
    final rawNet = json['net'];
    final net = rawNet is num ? rawNet.toDouble() : double.parse(rawNet.toString());
    return FriendActivityItem(
      kind: FriendActivityKind.values.byName(json['kind'] as String),
      refId: json['ref_id'] as String,
      name: json['name'] as String,
      net: net,
      date: DateTime.parse(json['activity_date'] as String),
      addedAt: json['added_at'] == null
          ? null
          : DateTime.parse(json['added_at'] as String).toLocal(),
      paidByMe: json['paid_by_me'] as bool?,
    );
  }
}
