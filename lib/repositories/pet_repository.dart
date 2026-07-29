import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/models/activity.dart';
import 'package:meowes_app/models/pet.dart';
import 'package:meowes_app/models/pet_memory.dart';

class PetRepository {
  final SupabaseClient _client;
  PetRepository(this._client);

  Future<Pet> getOrCreatePet() async {
    final row = await _client.rpc('get_or_create_pet');
    return Pet.fromJson(row as Map<String, dynamic>);
  }

  Future<Pet> feed() async {
    try {
      final row = await _client.rpc('feed_pet');
      return Pet.fromJson(row as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      if (e.message.contains('feed_cooldown')) throw FeedCooldownException();
      rethrow;
    }
  }

  Future<Pet> petTheCat() async {
    final row = await _client.rpc('pet_the_cat');
    return Pet.fromJson(row as Map<String, dynamic>);
  }

  Future<Pet> dailyCheckIn() async {
    try {
      final row = await _client.rpc('daily_check_in');
      return Pet.fromJson(row as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      if (e.message.contains('already_checked_in')) {
        throw AlreadyCheckedInException();
      }
      rethrow;
    }
  }

  Future<List<Activity>> getTodaysActivities() async {
    final rows = await _client.rpc('get_todays_activities') as List;
    return rows
        .map((r) => Activity.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<PetMemory> redeemActivity(String activityId) async {
    try {
      final row = await _client.rpc(
        'redeem_activity',
        params: {'p_activity_id': activityId},
      );
      return PetMemory.fromJson(row as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      if (e.message.contains('insufficient_coins')) {
        throw InsufficientCoinsException();
      }
      rethrow;
    }
  }

  Future<List<PetMemory>> getMemories() async {
    final me = _client.auth.currentUser!.id;
    final rows = await _client
        .from('pet_memories')
        .select()
        .eq('user_id', me)
        .order('completed_at', ascending: false);
    return (rows as List)
        .map((r) => PetMemory.fromJson(r as Map<String, dynamic>))
        .toList();
  }
}

final petRepositoryProvider = Provider<PetRepository>(
  (ref) => PetRepository(ref.watch(supabaseClientProvider)),
);
