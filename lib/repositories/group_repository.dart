import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/models/group.dart';

class GroupRepository {
  final SupabaseClient _client;
  GroupRepository(this._client);

  Future<Group> createGroup(String name) async {
    final me = _client.auth.currentUser!.id;
    final row = await _client
        .from('groups')
        .insert({'name': name, 'created_by': me})
        .select()
        .single();
    final group = Group.fromJson(row);
    await _client.from('group_members').insert({
      'group_id': group.id,
      'user_id': me,
    });
    return group;
  }

  Future<Group> joinByInviteCode(String code) async {
    // Calls the join_group_by_code RPC rather than selecting the groups
    // table directly: RLS locks groups to member-only SELECT, so a
    // non-member could never see the row to join it in the first place.
    // The RPC is SECURITY DEFINER and inserts the membership itself.
    try {
      final rows = await _client.rpc('join_group_by_code', params: {
        'invite_code_param': code,
      });
      final results = rows is List<dynamic> ? rows : const <dynamic>[];
      if (results.isEmpty) {
        throw StateError('Invalid invite code');
      }
      return Group.fromJson(results.first as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw StateError(e.message.contains('invalid invite code')
          ? 'Invalid invite code'
          : e.message);
    }
  }

  Stream<List<Group>> watchMyGroups() {
    final me = _client.auth.currentUser!.id;
    return _client
        .from('group_members')
        .stream(primaryKey: ['group_id', 'user_id'])
        .eq('user_id', me)
        .asyncMap((memberRows) async {
      final groupIds = memberRows.map((r) => r['group_id'] as String).toList();
      if (groupIds.isEmpty) return <Group>[];
      final groupRows = await _client.from('groups').select().inFilter('id', groupIds);
      return groupRows.map(Group.fromJson).toList();
    });
  }
}
