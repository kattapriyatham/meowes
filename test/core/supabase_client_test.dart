import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Mock the shared_preferences platform channel
    const channel = MethodChannel('plugins.flutter.io/shared_preferences');
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      if (methodCall.method == 'getAll') {
        return {};
      }
      return null;
    });
  });

  test('supabaseClientProvider returns a configured SupabaseClient', () async {
    // Initialize Supabase with test credentials
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test-anon-key',
    );

    final container = ProviderContainer();
    final client = container.read(supabaseClientProvider);
    expect(client, isA<SupabaseClient>());
  });
}



