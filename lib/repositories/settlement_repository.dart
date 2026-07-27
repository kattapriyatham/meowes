import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/models/settlement.dart';

class SettlementRepository {
  final SupabaseClient _client;
  SettlementRepository(this._client);

  Future<Settlement> markPaid({
    required String toUser,
    required int amountMinorUnits,
    String? groupId,
  }) async {
    final me = _client.auth.currentUser!.id;
    final row = await _client
        .from('settlements')
        .insert({
          'group_id': groupId,
          'from_user': me,
          'to_user': toUser,
          'amount': (amountMinorUnits / 100).toStringAsFixed(2),
          'status': 'pending_confirmation',
        })
        .select()
        .single();
    return Settlement.fromJson(row);
  }

  Future<void> confirmSettlement(String settlementId) async {
    // Without .select(), RLS silently blocking an unauthorized confirm
    // (e.g. the payer trying to self-confirm) would return success with
    // zero rows actually changed — checking the returned row makes that
    // failure visible instead of a no-op that looks like it worked.
    final rows = await _client
        .from('settlements')
        .update({
          'status': 'confirmed',
          'confirmed_at': DateTime.now().toIso8601String(),
        })
        .eq('id', settlementId)
        .select();
    if (rows.isEmpty) {
      throw StateError('Unable to confirm this settlement');
    }
  }

  Stream<List<Settlement>> watchPendingForMe() {
    final me = _client.auth.currentUser!.id;
    return _client
        .from('settlements')
        .stream(primaryKey: ['id'])
        .eq('status', 'pending_confirmation')
        .map((rows) => rows
            .map(Settlement.fromJson)
            .where((s) => s.toUser == me)
            .toList());
  }
}
