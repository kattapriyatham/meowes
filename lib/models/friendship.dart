enum FriendshipStatus { pending, accepted }

class Friendship {
  final String userIdA;
  final String userIdB;
  final FriendshipStatus status;
  final String requestedBy;

  Friendship({
    required this.userIdA,
    required this.userIdB,
    required this.status,
    required this.requestedBy,
  });

  factory Friendship.fromJson(Map<String, dynamic> json) => Friendship(
        userIdA: json['user_id_a'] as String,
        userIdB: json['user_id_b'] as String,
        status: (json['status'] as String) == 'accepted'
            ? FriendshipStatus.accepted
            : FriendshipStatus.pending,
        requestedBy: json['requested_by'] as String,
      );

  Map<String, dynamic> toJson() => {
        'user_id_a': userIdA,
        'user_id_b': userIdB,
        'status': status == FriendshipStatus.accepted ? 'accepted' : 'pending',
        'requested_by': requestedBy,
      };
}
