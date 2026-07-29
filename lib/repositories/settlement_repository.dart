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
    // The RPC transitions status to 'confirmed' AND credits the payer's
    // pet coins atomically; not_authorized/settlement_not_found surface
    // as PostgrestException the same way an empty-rows update used to.
    await _client.rpc(
      'confirm_settlement_and_award_coins',
      params: {'p_settlement_id': settlementId},
    );
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
