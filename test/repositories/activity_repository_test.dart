import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/models/activity_item.dart';
import 'package:meowes_app/repositories/activity_repository.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class _FakeRpcResult extends Fake implements PostgrestFilterBuilder<dynamic> {
  final dynamic data;
  _FakeRpcResult(this.data);

  @override
  Future<T> then<T>(FutureOr<T> Function(dynamic) onValue, {Function? onError}) {
    return Future<dynamic>.value(data).then(onValue, onError: onError);
  }
}

void main() {
  test('getMyActivityFeed maps rows and sorts newest-first', () async {
    final client = MockSupabaseClient();
    when(() => client.rpc('get_my_activity_feed')).thenAnswer((_) => _FakeRpcResult([
          {
            'kind': 'expense',
            'ref_id': 'e1',
            'title': 'Dinner',
            'counterpart_id': 'friend-1',
            'amount': 500,
            'is_mine': true,
            'occurred_at': '2026-08-10T00:00:00Z',
          },
          {
            'kind': 'pet_activity',
            'ref_id': 'p1',
            'title': 'Spa Day',
            'counterpart_id': null,
            'amount': 80,
            'is_mine': null,
            'occurred_at': '2026-08-12T00:00:00Z',
          },
          {
            'kind': 'settlement',
            'ref_id': 's1',
            'title': null,
            'counterpart_id': 'friend-1',
            'amount': 200,
            'is_mine': false,
            'occurred_at': '2026-08-11T00:00:00Z',
          },
        ]));

    final repo = ActivityRepository(client);
    final items = await repo.getMyActivityFeed();

    expect(items.map((i) => i.refId), ['p1', 's1', 'e1']); // newest first
    expect(items[2].kind, ActivityKind.expense);
    expect(items[2].isMine, true);
    expect(items[1].kind, ActivityKind.settlement);
    expect(items[1].counterpartId, 'friend-1');
    expect(items[0].kind, ActivityKind.petActivity);
    expect(items[0].amount, 80);
  });
}
