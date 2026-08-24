import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/models/activity.dart';
import 'package:meowes_app/models/food.dart';
import 'package:meowes_app/models/pet.dart';
import 'package:meowes_app/models/pet_memory.dart';
import 'package:meowes_app/models/special_food.dart';

class PetRepository {
  final SupabaseClient _client;
  PetRepository(this._client);

  Future<Pet> getOrCreatePet() async {
    final row = await _client.rpc('get_or_create_pet');
    return Pet.fromJson(row as Map<String, dynamic>);
  }

  Future<Pet> feed(FoodType food) async {
    try {
      final row = await _client.rpc(
        'feed_pet',
        params: {'p_food_key': food.key},
      );
      return Pet.fromJson(row as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      if (e.message.contains('feed_cooldown')) throw FeedCooldownException();
      rethrow;
    }
  }

  Future<Pet> updateName(String name) async {
    final me = _client.auth.currentUser!.id;
    final row = await _client
        .from('pets')
        .update({'name': name})
        .eq('user_id', me)
        .select()
        .single();
    return Pet.fromJson(row);
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

  // --- Special food inventory ---

  /// Purchasable special foods available in the shop.
  Future<List<SpecialFood>> getSpecialFoods() async {
    final rows = await _client.from('special_foods').select();
    return (rows as List)
        .map((r) => SpecialFood.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Special foods the user owns, with remaining uses.
  Future<List<FoodInventoryItem>> getFoodInventory() async {
    final rows = await _client.rpc('get_special_food_inventory') as List;
    return rows
        .map((r) => FoodInventoryItem.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Buy a special food. Deducts coins, adds to inventory.
  Future<FoodInventoryItem> purchaseSpecialFood(String specialFoodId) async {
    try {
      final row = await _client.rpc(
        'purchase_special_food',
        params: {'p_special_food_id': specialFoodId},
      );
      return FoodInventoryItem.fromJson({
        ...row as Map<String, dynamic>,
        'key': '',
        'name': '',
        'satiation_hours': 0,
        'coin_reward': 0,
        'bowl_asset': '',
      });
    } on PostgrestException catch (e) {
      if (e.message.contains('insufficient_coins')) {
        throw InsufficientCoinsException();
      }
      rethrow;
    }
  }

  /// Feed a special food from inventory. Consumes one use, grants rewards.
  Future<FeedSpecialResult> feedSpecialFood(String inventoryId) async {
    try {
      final row = await _client.rpc(
        'feed_special_food',
        params: {'p_inventory_id': inventoryId},
      );
      return FeedSpecialResult.fromJson(row as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      if (e.message.contains('feed_cooldown')) throw FeedCooldownException();
      rethrow;
    }
  }
}

final petRepositoryProvider = Provider<PetRepository>(
  (ref) => PetRepository(ref.watch(supabaseClientProvider)),
);
