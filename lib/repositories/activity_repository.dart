import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/models/activity_item.dart';

class ActivityRepository {
  final SupabaseClient _client;
  ActivityRepository(this._client);

  Future<List<ActivityItem>> getMyActivityFeed() async {
    final rows = await _client.rpc('get_my_activity_feed');
    final results = rows is List<dynamic> ? rows : const <dynamic>[];
    final items = results.map((r) => ActivityItem.fromJson(r as Map<String, dynamic>)).toList();
    items.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return items;
  }
}

final activityRepositoryProvider = Provider<ActivityRepository>(
  (ref) => ActivityRepository(ref.watch(supabaseClientProvider)),
);
