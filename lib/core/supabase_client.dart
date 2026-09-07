import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Bumped after any expense/settlement mutation (create/edit/delete/confirm)
/// so screens with one-shot `FutureBuilder` loads (Home overview, Friends
/// list, friend detail, expense detail) re-fetch even when they're revealed
/// by a `Navigator.pop` rather than a fresh push — plain route pops don't
/// rebuild the widget underneath on their own.
final dataChangedTickerProvider = StateProvider<int>((ref) => 0);

void notifyDataChanged(WidgetRef ref) {
  ref.read(dataChangedTickerProvider.notifier).state++;
}
