import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/models/app_user.dart';
import 'package:meowes_app/models/friendship.dart';

class InvalidInviteCodeException implements Exception {}

class CannotFriendSelfException implements Exception {}

class FriendRepository {
  final SupabaseClient _client;
  FriendRepository(this._client);

  Future<AppUser?> getMyProfile() async {
    final me = _client.auth.currentUser!.id;
    final row = await _client.from('users').select().eq('id', me).maybeSingle();
    return row == null ? null : AppUser.fromJson(row);
  }

  /// Looks up display name/avatar for other users via `public_profiles`
  /// (name, avatar_url only — RLS locks the base `users` table to
  /// own-row-only SELECT to keep phone_number private, see Task 2's fix).
  Future<List<AppUser>> getPublicProfiles(List<String> ids) async {
    if (ids.isEmpty) return [];
    final rows = await _client.from('public_profiles').select().inFilter('id', ids);
    return rows.map(AppUser.fromJson).toList();
  }

  Future<AppUser?> searchByPhone(String phone) async {
    // Calls the find_user_by_phone RPC rather than selecting the users
    // table directly: RLS locks users to own-row-only SELECT (Task 2's
    // RLS fix), so phone lookup goes through this SECURITY DEFINER
    // function instead, which also never returns phone_number itself back.
    final rows = await _client.rpc('find_user_by_phone', params: {'p_phone': phone});
    final results = rows is List<dynamic> ? rows : const <dynamic>[];
    if (results.isEmpty) return null;
    return AppUser.fromJson(results.first as Map<String, dynamic>);
  }

  /// This user's personal invite-link code (stable, `users.invite_code`).
  /// Own-row SELECT is allowed directly by RLS, unlike another user's code.
  Future<String> getMyInviteCode() async {
    final me = _client.auth.currentUser!.id;
    final row = await _client.from('users').select('invite_code').eq('id', me).single();
    return row['invite_code'] as String;
  }

  /// Redeems someone else's invite code, creating an already-accepted
  /// friendship in one step (see `join_friendship_by_code` for why no
  /// pending/accept round trip is needed here). Returns the new friend's
  /// public profile.
  Future<AppUser> joinByInviteCode(String code) async {
    try {
      final rows = await _client.rpc(
        'join_friendship_by_code',
        params: {'invite_code_param': code},
      );
      final results = rows is List<dynamic> ? rows : const <dynamic>[];
      if (results.isEmpty) throw InvalidInviteCodeException();
      return AppUser.fromJson(results.first as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      if (e.message.contains('invalid_invite_code')) throw InvalidInviteCodeException();
      if (e.message.contains('cannot_friend_self')) throw CannotFriendSelfException();
      rethrow;
    }
  }

  Future<void> sendFriendRequest(String toUserId) async {
    final me = _client.auth.currentUser!.id;
    final userIdA = me.compareTo(toUserId) < 0 ? me : toUserId;
    final userIdB = me.compareTo(toUserId) < 0 ? toUserId : me;
    await _client.from('friendships').insert({
      'user_id_a': userIdA,
      'user_id_b': userIdB,
      'status': 'pending',
      'requested_by': me,
    });
  }

  Future<void> acceptFriendRequest(String fromUserId) async {
    final me = _client.auth.currentUser!.id;
    final userIdA = me.compareTo(fromUserId) < 0 ? me : fromUserId;
    final userIdB = me.compareTo(fromUserId) < 0 ? fromUserId : me;
    await _client
        .from('friendships')
        .update({'status': 'accepted'})
        .eq('user_id_a', userIdA)
        .eq('user_id_b', userIdB);
  }

  Future<void> declineFriendRequest(String fromUserId) async {
    final me = _client.auth.currentUser!.id;
    final userIdA = me.compareTo(fromUserId) < 0 ? me : fromUserId;
    final userIdB = me.compareTo(fromUserId) < 0 ? fromUserId : me;
    await _client
        .from('friendships')
        .delete()
        .eq('user_id_a', userIdA)
        .eq('user_id_b', userIdB);
  }

  Future<void> sendFriendRemind(String friendUserId) async {
    await _client.rpc('send_friend_remind', params: {'p_friend_id': friendUserId});
  }

  /// Removes a friendship (either direction, any status). The row is scoped
  /// by the `user_id_a < user_id_b` ordering, so one delete covers it.
  Future<void> removeFriend(String friendUserId) async {
    final me = _client.auth.currentUser!.id;
    final userIdA = me.compareTo(friendUserId) < 0 ? me : friendUserId;
    final userIdB = me.compareTo(friendUserId) < 0 ? friendUserId : me;
    await _client
        .from('friendships')
        .delete()
        .eq('user_id_a', userIdA)
        .eq('user_id_b', userIdB);
  }

  /// Blocks a user: records the block and tears down any friendship /
  /// pending request. A blocked pair can't re-friend (invite link or
  /// request) and Remind pings between them are refused.
  Future<void> blockUser(String userId) async {
    await _client.rpc('block_user', params: {'p_target': userId});
  }

  /// Files a moderation report. [targetType] is 'expense' | 'group' | 'user'
  /// | 'remind'; [targetId] is that row's id (or the offending user's id for
  /// 'user' / 'remind'). [reason] is 'offensive' | 'harassment' | 'spam' |
  /// 'inappropriate' | 'other'.
  Future<void> reportContent({
    required String targetType,
    required String targetId,
    required String reason,
    String? details,
  }) async {
    await _client.from('content_reports').insert({
      'reporter_id': _client.auth.currentUser!.id,
      'target_type': targetType,
      'target_id': targetId,
      'reason': reason,
      if (details != null && details.trim().isNotEmpty) 'details': details.trim(),
    });
  }

  Stream<List<Friendship>> watchFriendships() {
    final me = _client.auth.currentUser!.id;
    return _client
        .from('friendships')
        .stream(primaryKey: ['user_id_a', 'user_id_b'])
        .map((rows) => rows
            .map(Friendship.fromJson)
            .where((f) => f.userIdA == me || f.userIdB == me)
            .toList());
  }
}
