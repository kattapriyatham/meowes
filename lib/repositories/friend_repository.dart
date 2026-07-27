import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/models/app_user.dart';
import 'package:meowes_app/models/friendship.dart';

class FriendRepository {
  final SupabaseClient _client;
  FriendRepository(this._client);

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
