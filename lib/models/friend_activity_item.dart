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

  FriendActivityItem({
    required this.kind,
    required this.refId,
    required this.name,
    required this.net,
    required this.date,
  });

  factory FriendActivityItem.fromJson(Map<String, dynamic> json) {
    final rawNet = json['net'];
    final net = rawNet is num ? rawNet.toDouble() : double.parse(rawNet.toString());
    return FriendActivityItem(
      kind: FriendActivityKind.values.byName(json['kind'] as String),
      refId: json['ref_id'] as String,
      name: json['name'] as String,
      net: net,
      date: DateTime.parse(json['activity_date'] as String),
    );
  }
}
