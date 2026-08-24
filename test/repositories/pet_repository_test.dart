import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/models/food.dart';
import 'package:meowes_app/models/pet.dart';
import 'package:meowes_app/repositories/pet_repository.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

class _MockUser extends Mock implements User {}

class _MockSupabaseQueryBuilder extends Mock implements SupabaseQueryBuilder {}

class _FakeRpcResult extends Fake implements PostgrestFilterBuilder<dynamic> {
  final dynamic _data;
  final Object? _error;
  _FakeRpcResult(this._data) : _error = null;
  _FakeRpcResult.error(this._error) : _data = null;

  @override
  Future<T> then<T>(
    FutureOr<T> Function(dynamic value) onValue, {
    Function? onError,
  }) {
    if (_error != null) {
      return Future<dynamic>.error(_error).then(onValue, onError: onError);
    }
    return Future<dynamic>.value(_data).then(onValue, onError: onError);
  }
}

class _FakeListResult extends Fake
    implements PostgrestFilterBuilder<PostgrestList> {
  final List<Map<String, dynamic>> _rows;
  _FakeListResult(this._rows);

  @override
  PostgrestFilterBuilder<PostgrestList> eq(String column, Object value) => this;

  @override
  PostgrestTransformBuilder<PostgrestList> order(
    String column, {
    bool ascending = false,
    bool nullsFirst = false,
    String? referencedTable,
  }) => this;

  @override
  Future<T> then<T>(
    FutureOr<T> Function(PostgrestList value) onValue, {
    Function? onError,
  }) => Future<PostgrestList>.value(_rows).then(onValue, onError: onError);
}

void main() {
  late _MockSupabaseClient client;
  late _MockGoTrueClient auth;
  late PetRepository repo;

  final samplePetJson = {
    'user_id': 'user-1',
    'name': 'Whiskers',
    'coins': 27,
    'mood_score': 70,
    'last_care_at': '2026-07-29T10:00:00.000Z',
    'last_fed_at': '2026-07-29T10:00:00.000Z',
    'last_checkin_at': '2026-07-29',
    'feed_streak_days': 1,
  };

  setUp(() {
    client = _MockSupabaseClient();
    auth = _MockGoTrueClient();
    final user = _MockUser();
    when(() => client.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(user);
    when(() => user.id).thenReturn('user-1');
    repo = PetRepository(client);
  });

  test('feed() parses the returned pet row', () async {
    when(
      () => client.rpc('feed_pet', params: {'p_food_key': 'fish'}),
    ).thenAnswer((_) => _FakeRpcResult(samplePetJson));

    final pet = await repo.feed(FoodType.fish);

    expect(pet.coins, 27);
    expect(pet.mood, MoodState.happy);
  });

  test('feed() throws FeedCooldownException on cooldown error', () async {
    when(
      () => client.rpc('feed_pet', params: {'p_food_key': 'treats'}),
    ).thenAnswer(
      (_) => _FakeRpcResult.error(PostgrestException(message: 'feed_cooldown')),
    );

    expect(
      () => repo.feed(FoodType.treats),
      throwsA(isA<FeedCooldownException>()),
    );
  });

  test(
    'dailyCheckIn() throws AlreadyCheckedInException when already done',
    () async {
      when(() => client.rpc('daily_check_in')).thenAnswer(
        (_) => _FakeRpcResult.error(
          PostgrestException(message: 'already_checked_in'),
        ),
      );

      expect(
        () => repo.dailyCheckIn(),
        throwsA(isA<AlreadyCheckedInException>()),
      );
    },
  );

  test(
    'redeemActivity() throws InsufficientCoinsException when too poor',
    () async {
      when(
        () => client.rpc(
          'redeem_activity',
          params: {'p_activity_id': 'activity-1'},
        ),
      ).thenAnswer(
        (_) => _FakeRpcResult.error(
          PostgrestException(message: 'insufficient_coins'),
        ),
      );

      expect(
        () => repo.redeemActivity('activity-1'),
        throwsA(isA<InsufficientCoinsException>()),
      );
    },
  );

  test('getMemories() returns memories for the current user', () async {
    final builder = _MockSupabaseQueryBuilder();
    when(() => client.from('pet_memories')).thenAnswer((_) => builder);
    when(() => builder.select()).thenAnswer(
      (_) => _FakeListResult([
        {
          'id': 'mem-1',
          'activity_id': 'activity-1',
          'activity_name': 'Park Picnic',
          'caption': 'We spent the afternoon under a big tree.',
          'image_asset': 'assets/images/activities/park_picnic.webp',
          'coins_spent': 60,
          'completed_at': '2026-07-29T10:00:00.000Z',
        },
      ]),
    );

    final memories = await repo.getMemories();

    expect(memories, hasLength(1));
    expect(memories.first.activityName, 'Park Picnic');
  });
}
