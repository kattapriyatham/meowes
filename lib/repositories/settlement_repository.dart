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
    await _client.from('settlements').update({
      'status': 'confirmed',
      'confirmed_at': DateTime.now().toIso8601String(),
    }).eq('id', settlementId);
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
