import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowes_app/core/push_notifications.dart';

void main() {
  group('decodeNotificationPayload', () {
    test('decodes a JSON-encoded string map', () {
      final raw = jsonEncode({'type': 'pet_hungry', 'food_key': 'fish'});
      expect(decodeNotificationPayload(raw), {'type': 'pet_hungry', 'food_key': 'fish'});
    });

    test('returns an empty map for null', () {
      expect(decodeNotificationPayload(null), <String, String>{});
    });

    test('returns an empty map for invalid JSON', () {
      expect(decodeNotificationPayload('not json'), <String, String>{});
    });
  });
}
