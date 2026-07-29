# Pet / Coin / Mood Companion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every user a persistent companion cat with a coin economy (earned via daily check-in, feeding, and settling up) and a mood state (driven only by care-action engagement, never by debt), spendable on handcrafted Activities that produce permanent Memory journal entries.

**Architecture:** Follows the existing app's plain-repository + Riverpod `Provider` pattern (no `AsyncNotifier`/codegen). All mutating logic (coin awards, mood decay, cooldowns, streaks, activity redemption) lives in Postgres `security definer` RPC functions — matching the codebase's existing convention (see `get_friend_activity`, `join_group_by_code`) of doing cross-cutting/atomic writes server-side rather than in Dart. Reads that don't need cross-user logic (the memory journal) use plain RLS-scoped `select()` calls like every other repository.

**Tech Stack:** Flutter, Riverpod 2.x (`Provider`, `ConsumerWidget`), Supabase (Postgres + RLS + RPC), `mocktail` for repository tests. No new packages required — mood/activity art uses the same `Image.asset` + `errorBuilder` fallback pattern as the existing `_CatPlaceholder`.

## Global Constraints

- Money/coins are never purchased with real money (spec, Section 1 & 4).
- Coins are never earned by logging/creating expenses (spec, Section 1).
- Mood is visual-only and never affects coin earning/spending or expense-sharing functionality (spec, Section 2).
- Feeding costs nothing to the user but is capped at once per 3 hours (spec, Section 1).
- Daily check-in awards +5 coins, once per calendar day (spec, Section 1).
- Feed streak of 7 consecutive days awards a one-time +10 bonus (spec, Section 1).
- Settling a balance in full awards +20 coins to the payer (spec, Section 1).
- Petting is free and unbounded — no coin reward, mood only (spec, Section 1).
- Mood scale: discrete `MoodState` enum backed by a 0–100 internal score; +10 per care action (feed or pet), -15 per full day with no care action, clamped to [0, 100] (decision made this session; tunable later, not a placeholder).
- Mood bands: 0–24 `sad`, 25–59 `content`, 60–84 `happy`, 85–100 `ecstatic`.
- New pet starts at 25 coins, mood score 60 (`happy`) (decision made this session).
- Activities: 3–5 shown at a time, pre-generated art + fixed captions only, no dynamically composed cosmetics (spec, Section 3). Rotation is deterministic per-user-per-day (decision made this session) — no cron job needed.
- Every new table gets RLS enabled with named, scoped policies, following `docs/superpowers/specs/2026-07-27-core-expense-splitting-design.md`'s established conventions (see `supabase/migrations/0001_init_schema.sql`).
- New migrations use the `YYYYMMDDHHMMSS_description.sql` naming convention (today: `20260729`).

## UI/UX Design Guidelines

Sourced via the ui-ux-pro-max design skill, filtered to what's consistent with
the app's existing warm-paper `GlassTokens` system — its default recommendation
for this feature type (claymorphism, orange/blue palette) was **not** adopted,
since introducing a second palette would fight the "feels like the same app"
goal. Only the token-agnostic interaction/accessibility principles apply:

- **No new colors.** Mood is communicated by mapping `MoodState` onto tokens
  that already exist: `happy`/`ecstatic` tint toward `t.positive`, `sad` tints
  toward `t.negative` (both used at low alpha, as a soft border/glow — never
  full-saturation), `content` stays neutral (`t.textSecondary`/no tint). No new
  hex values anywhere in this feature.
- **Feedback proportional to frequency.** A `SnackBar` per tap is too heavy for
  actions users repeat often (feed, pet) — reserve `SnackBar` for infrequent,
  meaningful events (daily check-in, feed cooldown, insufficient coins).
  Frequent actions get a lightweight inline animated indicator instead (a
  small "+2" that fades/rises next to the tapped button, `AnimatedSwitcher`/
  implicit animation, 150–300ms) — "success feedback" without interrupting.
- **Press feedback on every tappable element.** Feed/pet icon buttons and
  activity redeem buttons get an `AnimatedScale` (~0.92 on press, per standard
  active-state guidance) so taps feel acknowledged immediately, not just after
  the network round-trip resolves.
- **Icon-only buttons need labels.** `SoftIconButton` for feed/pet has no text
  — wrap each in `Tooltip`/`Semantics` with a real label ("Feed", "Pet") so
  screen readers and long-press hints both work. Existing `SoftIconButton`
  default size (48) already clears the 44×44 minimum touch target.
- **Respect reduced motion.** The codebase already has `motionReduced(context)`
  (`lib/core/a11y/accessibility.dart`, used by `SkeletonLoader`) — any new
  implicit/explicit animation in this feature checks it and skips/shortens
  the animation when true, rather than introducing a second convention.
- **Proactive affordance over reactive error.** On the Activities screen, an
  activity the user can't afford should look visibly disabled (dimmed
  `PillButton`, cost text muted) rather than looking identical to an
  affordable one and only failing after tap — catching
  `InsufficientCoinsException` stays as a safety net, not the primary signal.
- **Journal stays a timeline, not a grid.** The spec calls memories a
  "chronological journal" — a single-column reverse-chronological list (as
  already planned) matches that narrative framing better than a grid, which
  would read as a shop/gallery instead of a diary.
- **Flutter list hygiene.** `ListView.builder`/`ListView.separated` (already
  planned) plus a `ValueKey` per item for the memory journal list, so item
  state survives list reordering/rebuilds as new memories are added.

---

### Task 1: Database schema — `pets`, `activities`, `pet_memories` tables

**Files:**
- Create: `supabase/migrations/20260729120000_pet_companion_schema.sql`

**Interfaces:**
- Produces: tables `pets(user_id, coins, mood_score, last_care_at, last_fed_at, last_checkin_at, feed_streak_days, last_feed_streak_date, created_at)`, `activities(id, key, name, category, coin_cost, image_asset, caption)`, `pet_memories(id, user_id, activity_id, activity_name, caption, image_asset, coins_spent, completed_at)`. Later tasks' RPCs and the Dart models read/write these exact column names.

- [ ] **Step 1: Write the migration**

```sql
-- Pets: one row per user, holds coin balance and mood state.
create table pets (
  user_id uuid primary key references users(id) on delete cascade,
  coins integer not null default 25 check (coins >= 0),
  mood_score integer not null default 60 check (mood_score between 0 and 100),
  last_care_at timestamptz not null default now(),
  last_fed_at timestamptz,
  last_checkin_at date,
  feed_streak_days integer not null default 0,
  last_feed_streak_date date,
  created_at timestamptz not null default now()
);

alter table pets enable row level security;

create policy pets_select_owner on pets
  for select to authenticated using (auth.uid() = user_id);

create policy pets_insert_owner on pets
  for insert to authenticated with check (auth.uid() = user_id);

create policy pets_update_owner on pets
  for update to authenticated using (auth.uid() = user_id);

-- Activities: shared read-only catalog, managed by migrations only.
create table activities (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  name text not null,
  category text not null,
  coin_cost integer not null check (coin_cost > 0),
  image_asset text not null,
  caption text not null
);

alter table activities enable row level security;

create policy activities_select_all on activities
  for select to authenticated using (true);

insert into activities (key, name, category, coin_cost, image_asset, caption) values
  ('morning_walk', 'Morning Walk', 'Walks', 20, 'assets/images/activities/morning_walk.webp', 'We watched the sun come up together. You walk too fast, by the way.'),
  ('watching_the_rain', 'Watching the Rain', 'Relaxation', 30, 'assets/images/activities/watching_the_rain.webp', 'We just sat by the window and watched the rain fall. Perfect nap weather.'),
  ('spa_day', 'Spa Day', 'Grooming', 80, 'assets/images/activities/spa_day.webp', 'You brushed me for an hour. I pretended not to enjoy it. I enjoyed it.'),
  ('park_picnic', 'Park Picnic', 'Outdoor Adventures', 60, 'assets/images/activities/park_picnic.webp', 'We spent the afternoon under a big tree. I almost stole your sandwich.'),
  ('beach_trip', 'Beach Trip', 'Outdoor Adventures', 150, 'assets/images/activities/beach_trip.webp', 'I do not like sand. I like you. Mixed feelings about today.'),
  ('camping', 'Camping', 'Outdoor Adventures', 220, 'assets/images/activities/camping.webp', 'We slept under the stars. I kept watch all night, obviously.'),
  ('chased_a_butterfly', 'Chased a Butterfly', 'Funny Moments', 25, 'assets/images/activities/chased_a_butterfly.webp', 'I almost had it. Almost. Did you see that jump though?'),
  ('birthday_celebration', 'Birthday Celebration', 'Special Occasions', 500, 'assets/images/activities/birthday_celebration.webp', 'You made today feel special. Thank you for always showing up for me.');

-- Pet memories: permanent journal of completed activities.
create table pet_memories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  activity_id uuid not null references activities(id),
  activity_name text not null,
  caption text not null,
  image_asset text not null,
  coins_spent integer not null,
  completed_at timestamptz not null default now()
);

create index idx_pet_memories_user on pet_memories(user_id, completed_at desc);

alter table pet_memories enable row level security;

create policy pet_memories_select_owner on pet_memories
  for select to authenticated using (auth.uid() = user_id);

create policy pet_memories_insert_owner on pet_memories
  for insert to authenticated with check (auth.uid() = user_id);
```

- [ ] **Step 2: Apply the migration locally and verify**

Run: `cd supabase && supabase db reset` (or `supabase migration up` if you don't want a full reset)
Expected: migration applies with no errors; `select * from activities;` returns 8 rows.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260729120000_pet_companion_schema.sql
git commit -m "feat: add pets, activities, pet_memories schema"
```

---

### Task 2: Database RPCs — coin/mood mutations

**Files:**
- Create: `supabase/migrations/20260729121000_pet_companion_rpcs.sql`

**Interfaces:**
- Consumes: `pets`, `activities`, `pet_memories` tables from Task 1.
- Produces: RPC functions `get_or_create_pet()`, `feed_pet()`, `pet_the_cat()`, `daily_check_in()`, `get_todays_activities()`, `redeem_activity(p_activity_id uuid)`, each returning a row shape matching a table above (or `setof activities`). `PetRepository` (Task 4) calls these by exact name with these exact param names.

- [ ] **Step 1: Write the migration**

```sql
-- Applies mood decay lazily: -15 mood per full 24h elapsed since last_care_at.
create or replace function apply_mood_decay(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_days_elapsed integer;
begin
  select floor(extract(epoch from (now() - last_care_at)) / 86400)::int
    into v_days_elapsed
    from pets where user_id = p_user_id;

  if v_days_elapsed is not null and v_days_elapsed >= 1 then
    update pets
    set mood_score = greatest(mood_score - (15 * v_days_elapsed), 0),
        last_care_at = last_care_at + (v_days_elapsed || ' days')::interval
    where user_id = p_user_id;
  end if;
end;
$$;
revoke all on function apply_mood_decay(uuid) from public;

create or replace function get_or_create_pet()
returns pets
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pet pets;
begin
  select * into v_pet from pets where user_id = auth.uid();
  if not found then
    insert into pets (user_id) values (auth.uid()) returning * into v_pet;
    return v_pet;
  end if;
  perform apply_mood_decay(auth.uid());
  select * into v_pet from pets where user_id = auth.uid();
  return v_pet;
end;
$$;
revoke all on function get_or_create_pet() from public;
grant execute on function get_or_create_pet() to authenticated;

create or replace function feed_pet()
returns pets
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pet pets;
  v_today date := current_date;
  v_streak integer;
  v_bonus integer;
begin
  perform get_or_create_pet();

  select * into v_pet from pets where user_id = auth.uid() for update;

  if v_pet.last_fed_at is not null and v_pet.last_fed_at > now() - interval '3 hours' then
    raise exception 'feed_cooldown';
  end if;

  if v_pet.last_feed_streak_date = v_today - 1 then
    v_streak := v_pet.feed_streak_days + 1;
  elsif v_pet.last_feed_streak_date = v_today then
    v_streak := v_pet.feed_streak_days;
  else
    v_streak := 1;
  end if;

  v_bonus := case when v_streak = 7 then 10 else 0 end;

  update pets
  set coins = coins + 2 + v_bonus,
      mood_score = least(mood_score + 10, 100),
      last_fed_at = now(),
      last_care_at = now(),
      feed_streak_days = case when v_streak = 7 then 0 else v_streak end,
      last_feed_streak_date = v_today
  where user_id = auth.uid()
  returning * into v_pet;

  return v_pet;
end;
$$;
revoke all on function feed_pet() from public;
grant execute on function feed_pet() to authenticated;

create or replace function pet_the_cat()
returns pets
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pet pets;
begin
  perform get_or_create_pet();

  update pets
  set mood_score = least(mood_score + 10, 100),
      last_care_at = now()
  where user_id = auth.uid()
  returning * into v_pet;

  return v_pet;
end;
$$;
revoke all on function pet_the_cat() from public;
grant execute on function pet_the_cat() to authenticated;

create or replace function daily_check_in()
returns pets
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pet pets;
begin
  perform get_or_create_pet();

  select * into v_pet from pets where user_id = auth.uid() for update;

  if v_pet.last_checkin_at = current_date then
    raise exception 'already_checked_in';
  end if;

  update pets
  set coins = coins + 5,
      last_checkin_at = current_date
  where user_id = auth.uid()
  returning * into v_pet;

  return v_pet;
end;
$$;
revoke all on function daily_check_in() from public;
grant execute on function daily_check_in() to authenticated;

-- Deterministic per-user-per-day rotation: same 4 activities all day for
-- one user, different set for a different user or a different day.
create or replace function get_todays_activities()
returns setof activities
language sql
stable
security definer
set search_path = public
as $$
  select * from activities
  order by md5(auth.uid()::text || current_date::text || id::text)
  limit 4;
$$;
revoke all on function get_todays_activities() from public;
grant execute on function get_todays_activities() to authenticated;

create or replace function redeem_activity(p_activity_id uuid)
returns pet_memories
language plpgsql
security definer
set search_path = public
as $$
declare
  v_activity activities;
  v_pet pets;
  v_memory pet_memories;
begin
  select * into v_activity from activities where id = p_activity_id;
  if not found then
    raise exception 'activity_not_found';
  end if;

  perform get_or_create_pet();

  select * into v_pet from pets where user_id = auth.uid() for update;

  if v_pet.coins < v_activity.coin_cost then
    raise exception 'insufficient_coins';
  end if;

  update pets set coins = coins - v_activity.coin_cost where user_id = auth.uid();

  insert into pet_memories (user_id, activity_id, activity_name, caption, image_asset, coins_spent)
  values (auth.uid(), v_activity.id, v_activity.name, v_activity.caption, v_activity.image_asset, v_activity.coin_cost)
  returning * into v_memory;

  return v_memory;
end;
$$;
revoke all on function redeem_activity(uuid) from public;
grant execute on function redeem_activity(uuid) to authenticated;
```

- [ ] **Step 2: Apply and manually verify each RPC**

Run: `cd supabase && supabase db reset`
Then, via `supabase db shell` or the SQL editor, as a test: `select get_or_create_pet();` should insert and return a row with `coins = 25, mood_score = 60`. Calling `feed_pet()` immediately after should return `coins = 27, mood_score = 70`. Calling `feed_pet()` again immediately should raise `feed_cooldown`.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260729121000_pet_companion_rpcs.sql
git commit -m "feat: add pet coin/mood RPC functions"
```

---

### Task 3: Dart domain models

**Files:**
- Create: `lib/models/pet.dart`
- Create: `lib/models/activity.dart`
- Create: `lib/models/pet_memory.dart`

**Interfaces:**
- Consumes: nothing (leaf models).
- Produces: `MoodState` enum + `moodStateFromScore(int)`, `Pet` (fields: `userId, coins, moodScore, mood (getter), lastCareAt, lastFedAt, lastCheckinAt, feedStreakDays`) with `Pet.fromJson`, `Activity` (fields: `id, key, name, category, coinCost, imageAsset, caption`) with `Activity.fromJson`, `PetMemory` (fields: `id, activityId, activityName, caption, imageAsset, coinsSpent, completedAt`) with `PetMemory.fromJson`. `PetRepository` (Task 4) and UI (Tasks 7-9) depend on these exact names.

- [ ] **Step 1: Write `lib/models/pet.dart`**

```dart
enum MoodState { sad, content, happy, ecstatic }

MoodState moodStateFromScore(int score) {
  if (score >= 85) return MoodState.ecstatic;
  if (score >= 60) return MoodState.happy;
  if (score >= 25) return MoodState.content;
  return MoodState.sad;
}

class Pet {
  final String userId;
  final int coins;
  final int moodScore;
  final DateTime lastCareAt;
  final DateTime? lastFedAt;
  final DateTime? lastCheckinAt;
  final int feedStreakDays;

  const Pet({
    required this.userId,
    required this.coins,
    required this.moodScore,
    required this.lastCareAt,
    this.lastFedAt,
    this.lastCheckinAt,
    required this.feedStreakDays,
  });

  MoodState get mood => moodStateFromScore(moodScore);

  factory Pet.fromJson(Map<String, dynamic> json) => Pet(
        userId: json['user_id'] as String,
        coins: json['coins'] as int,
        moodScore: json['mood_score'] as int,
        lastCareAt: DateTime.parse(json['last_care_at'] as String),
        lastFedAt: json['last_fed_at'] == null
            ? null
            : DateTime.parse(json['last_fed_at'] as String),
        lastCheckinAt: json['last_checkin_at'] == null
            ? null
            : DateTime.parse(json['last_checkin_at'] as String),
        feedStreakDays: json['feed_streak_days'] as int,
      );
}

class FeedCooldownException implements Exception {}

class AlreadyCheckedInException implements Exception {}

class InsufficientCoinsException implements Exception {}
```

- [ ] **Step 2: Write `lib/models/activity.dart`**

```dart
class Activity {
  final String id;
  final String key;
  final String name;
  final String category;
  final int coinCost;
  final String imageAsset;
  final String caption;

  const Activity({
    required this.id,
    required this.key,
    required this.name,
    required this.category,
    required this.coinCost,
    required this.imageAsset,
    required this.caption,
  });

  factory Activity.fromJson(Map<String, dynamic> json) => Activity(
        id: json['id'] as String,
        key: json['key'] as String,
        name: json['name'] as String,
        category: json['category'] as String,
        coinCost: json['coin_cost'] as int,
        imageAsset: json['image_asset'] as String,
        caption: json['caption'] as String,
      );
}
```

- [ ] **Step 3: Write `lib/models/pet_memory.dart`**

```dart
class PetMemory {
  final String id;
  final String activityId;
  final String activityName;
  final String caption;
  final String imageAsset;
  final int coinsSpent;
  final DateTime completedAt;

  const PetMemory({
    required this.id,
    required this.activityId,
    required this.activityName,
    required this.caption,
    required this.imageAsset,
    required this.coinsSpent,
    required this.completedAt,
  });

  factory PetMemory.fromJson(Map<String, dynamic> json) => PetMemory(
        id: json['id'] as String,
        activityId: json['activity_id'] as String,
        activityName: json['activity_name'] as String,
        caption: json['caption'] as String,
        imageAsset: json['image_asset'] as String,
        coinsSpent: json['coins_spent'] as int,
        completedAt: DateTime.parse(json['completed_at'] as String),
      );
}
```

- [ ] **Step 4: Verify it compiles**

Run: `flutter analyze lib/models/pet.dart lib/models/activity.dart lib/models/pet_memory.dart`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/models/pet.dart lib/models/activity.dart lib/models/pet_memory.dart
git commit -m "feat: add Pet, Activity, PetMemory domain models"
```

---

### Task 4: `PetRepository`

**Files:**
- Create: `lib/repositories/pet_repository.dart`

**Interfaces:**
- Consumes: `Pet.fromJson`, `Activity.fromJson`, `PetMemory.fromJson` (Task 3); `supabaseClientProvider` from `lib/core/supabase_client.dart`; RPCs from Task 2.
- Produces: `PetRepository` with methods `Future<Pet> getOrCreatePet()`, `Future<Pet> feed()`, `Future<Pet> petTheCat()`, `Future<Pet> dailyCheckIn()`, `Future<List<Activity>> getTodaysActivities()`, `Future<PetMemory> redeemActivity(String activityId)`, `Future<List<PetMemory>> getMemories()`; and `final petRepositoryProvider = Provider<PetRepository>(...)`. Tasks 7-9 (UI) depend on these exact method names/signatures.

- [ ] **Step 1: Write the repository**

```dart
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
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/repositories/pet_repository.dart`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/repositories/pet_repository.dart
git commit -m "feat: add PetRepository"
```

---

### Task 5: `PetRepository` unit tests

**Files:**
- Create: `test/repositories/pet_repository_test.dart`

**Interfaces:**
- Consumes: `PetRepository`, `Pet`, `Activity`, `PetMemory`, exceptions from Tasks 3-4. Follows the `Fake`-based mocking pattern from `test/repositories/settlement_repository_test.dart` (mocktail can't reliably stub Postgrest's `then()`-based Future chain, so hand-written `Fake`s implement just `then()` for each shape needed).

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/models/pet.dart';
import 'package:meowes_app/repositories/pet_repository.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

class _MockUser extends Mock implements User {}

class _MockSupabaseQueryBuilder extends Mock implements SupabaseQueryBuilder {}

class _FakeRpcResult extends Fake implements PostgrestTransformBuilder<dynamic> {
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

class _FakeListResult extends Fake implements PostgrestFilterBuilder<dynamic> {
  final List<Map<String, dynamic>> _rows;
  _FakeListResult(this._rows);

  @override
  PostgrestFilterBuilder<dynamic> eq(String column, Object value) => this;

  @override
  PostgrestTransformBuilder<dynamic> order(
    String column, {
    bool ascending = true,
    bool nullsFirst = false,
    String? referencedTable,
  }) =>
      this;

  @override
  Future<T> then<T>(
    FutureOr<T> Function(dynamic value) onValue, {
    Function? onError,
  }) =>
      Future<dynamic>.value(_rows).then(onValue, onError: onError);
}

void main() {
  late _MockSupabaseClient client;
  late _MockGoTrueClient auth;
  late PetRepository repo;

  final samplePetJson = {
    'user_id': 'user-1',
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
    when(() => client.rpc('feed_pet'))
        .thenReturn(_FakeRpcResult(samplePetJson));

    final pet = await repo.feed();

    expect(pet.coins, 27);
    expect(pet.mood, MoodState.happy);
  });

  test('feed() throws FeedCooldownException on cooldown error', () async {
    when(() => client.rpc('feed_pet')).thenReturn(
      _FakeRpcResult.error(
        PostgrestException(message: 'feed_cooldown'),
      ),
    );

    expect(() => repo.feed(), throwsA(isA<FeedCooldownException>()));
  });

  test('dailyCheckIn() throws AlreadyCheckedInException when already done',
      () async {
    when(() => client.rpc('daily_check_in')).thenReturn(
      _FakeRpcResult.error(
        PostgrestException(message: 'already_checked_in'),
      ),
    );

    expect(
      () => repo.dailyCheckIn(),
      throwsA(isA<AlreadyCheckedInException>()),
    );
  });

  test('redeemActivity() throws InsufficientCoinsException when too poor',
      () async {
    when(() => client.rpc(
          'redeem_activity',
          params: {'p_activity_id': 'activity-1'},
        )).thenReturn(
      _FakeRpcResult.error(
        PostgrestException(message: 'insufficient_coins'),
      ),
    );

    expect(
      () => repo.redeemActivity('activity-1'),
      throwsA(isA<InsufficientCoinsException>()),
    );
  });

  test('getMemories() returns memories for the current user', () async {
    final builder = _MockSupabaseQueryBuilder();
    when(() => client.from('pet_memories')).thenReturn(builder);
    when(() => builder.select()).thenReturn(_FakeListResult([
      {
        'id': 'mem-1',
        'activity_id': 'activity-1',
        'activity_name': 'Park Picnic',
        'caption': 'We spent the afternoon under a big tree.',
        'image_asset': 'assets/images/activities/park_picnic.webp',
        'coins_spent': 60,
        'completed_at': '2026-07-29T10:00:00.000Z',
      }
    ]));

    final memories = await repo.getMemories();

    expect(memories, hasLength(1));
    expect(memories.first.activityName, 'Park Picnic');
  });
}
```

- [ ] **Step 2: Run the tests to verify they pass**

Run: `flutter test test/repositories/pet_repository_test.dart`
Expected: all 5 tests PASS (the repository from Task 4 already exists, so this task is verifying the test doubles match the real RPC/exception behavior — if any test fails, check the `_Fake*` classes' method overrides against the actual `supabase_flutter` version in `pubspec.yaml`, e.g. `order()`'s exact named parameters can shift between versions).

- [ ] **Step 3: Commit**

```bash
git add test/repositories/pet_repository_test.dart
git commit -m "test: add PetRepository unit tests"
```

---

### Task 6: Wire settle-up coin award into existing settlement flow

**Files:**
- Create: `supabase/migrations/20260729122000_confirm_settlement_awards_coins.sql`
- Modify: `lib/repositories/settlement_repository.dart:28-44` (the `confirmSettlement` method)
- Modify: `test/repositories/settlement_repository_test.dart` (update the existing confirm-settlement test to match the new RPC-based call)

**Interfaces:**
- Consumes: `settlements` and `pets` tables (existing + Task 1).
- Produces: RPC `confirm_settlement_and_award_coins(p_settlement_id uuid) returns settlements`. `SettlementRepository.confirmSettlement(String settlementId)` keeps its existing `Future<void>` signature and both existing call sites (`lib/features/activity/activity_screen.dart:309`, `lib/features/notifications/notifications_screen.dart:179`) are unaffected.

- [ ] **Step 1: Write the migration**

```sql
-- Confirming a settlement now also credits the payer's pet coins,
-- atomically with the status transition, idempotent on double-confirm.
create or replace function confirm_settlement_and_award_coins(p_settlement_id uuid)
returns settlements
language plpgsql
security definer
set search_path = public
as $$
declare
  v_settlement settlements;
begin
  select * into v_settlement from settlements where id = p_settlement_id for update;

  if not found then
    raise exception 'settlement_not_found';
  end if;

  if v_settlement.to_user <> auth.uid() then
    raise exception 'not_authorized';
  end if;

  if v_settlement.status = 'confirmed' then
    return v_settlement;
  end if;

  update settlements
  set status = 'confirmed', confirmed_at = now()
  where id = p_settlement_id
  returning * into v_settlement;

  insert into pets (user_id) values (v_settlement.from_user)
    on conflict (user_id) do nothing;

  update pets set coins = coins + 20 where user_id = v_settlement.from_user;

  return v_settlement;
end;
$$;
revoke all on function confirm_settlement_and_award_coins(uuid) from public;
grant execute on function confirm_settlement_and_award_coins(uuid) to authenticated;
```

- [ ] **Step 2: Apply and verify**

Run: `cd supabase && supabase db reset`
Expected: migration applies with no errors.

- [ ] **Step 3: Update `confirmSettlement` to call the RPC**

In `lib/repositories/settlement_repository.dart`, replace the body of `confirmSettlement`:

```dart
  Future<void> confirmSettlement(String settlementId) async {
    // The RPC transitions status to 'confirmed' AND credits the payer's
    // pet coins atomically; not_authorized/settlement_not_found surface
    // as PostgrestException the same way an empty-rows update used to.
    await _client.rpc(
      'confirm_settlement_and_award_coins',
      params: {'p_settlement_id': settlementId},
    );
  }
```

- [ ] **Step 4: Update the existing repository test**

Open `test/repositories/settlement_repository_test.dart`, find the test(s) exercising `confirmSettlement` (built against the old `.update().eq().select()` chain), and change them to stub `client.rpc('confirm_settlement_and_award_coins', params: {'p_settlement_id': ...})` returning a `_FakeSingleRow`-equivalent (reuse whatever fake class that file already defines for a single-row RPC result; if none exists, add one modeled on this plan's `_FakeRpcResult` from Task 5). Also add a test asserting a `PostgrestException` from the RPC (e.g. `not_authorized`) propagates out of `confirmSettlement` unchanged.

- [ ] **Step 5: Run the settlement repository tests**

Run: `flutter test test/repositories/settlement_repository_test.dart`
Expected: all tests PASS, including the updated confirm-settlement test(s).

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260729122000_confirm_settlement_awards_coins.sql lib/repositories/settlement_repository.dart test/repositories/settlement_repository_test.dart
git commit -m "feat: award settle-up coins atomically on settlement confirmation"
```

---

### Task 7: Pet card UI on the home screen

**Files:**
- Modify: `lib/features/home/home_screen.dart` (the `_CatPlaceholder` widget at lines 376-408 and `_BalanceCard` at lines 292-374)

**Interfaces:**
- Consumes: `petRepositoryProvider`, `Pet`, `MoodState` (Tasks 3-4).
- Produces: no new public interface — this is a leaf UI change consumed only by the app shell.

- [ ] **Step 1: Add the new imports to the top of `home_screen.dart`**

```dart
import 'package:meowes_app/core/a11y/accessibility.dart';
import 'package:meowes_app/models/pet.dart';
import 'package:meowes_app/repositories/pet_repository.dart';
```

(`flutter_riverpod`'s `ConsumerWidget`/`ConsumerStatefulWidget`, `Theme`, and `GlassTokens` are already imported in this file since `HomeScreen` itself is a `ConsumerWidget`. `motionReduced` comes from `lib/core/a11y/accessibility.dart`, already used by `SkeletonLoader` — reuse the same helper rather than introducing a second reduced-motion check.)

- [ ] **Step 2: Replace `_CatPlaceholder` with a mood-aware, interactive `_PetCatWidget`**

Design notes (see "UI/UX Design Guidelines" above): mood is shown as a soft
colored glow behind the cat using only existing `GlassTokens` (no new
colors), feed/pet give an inline "+N"/"♥" pop next to the coin counter
instead of a `SnackBar` (too heavy for a frequently-repeated action), the
check-in `SnackBar` stays since it's once-a-day, and both icon buttons get a
`Tooltip` label since they're icon-only.

```dart
// ── Pet cat, mood-aware and interactive ────────────────────────────────
class _PetCatWidget extends ConsumerStatefulWidget {
  final double width;
  const _PetCatWidget({required this.width});

  @override
  ConsumerState<_PetCatWidget> createState() => _PetCatWidgetState();
}

class _PetCatWidgetState extends ConsumerState<_PetCatWidget> {
  Pet? _pet;
  bool _busy = false;
  String? _popText;

  @override
  void initState() {
    super.initState();
    _loadAndCheckIn();
  }

  Future<void> _loadAndCheckIn() async {
    final repo = ref.read(petRepositoryProvider);
    final pet = await repo.getOrCreatePet();
    if (!mounted) return;
    setState(() => _pet = pet);

    try {
      final afterCheckIn = await repo.dailyCheckIn();
      if (!mounted) return;
      setState(() => _pet = afterCheckIn);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Daily check-in: +5 coins')),
        );
      }
    } on AlreadyCheckedInException {
      // Already checked in today — silent no-op.
    }
  }

  void _showPop(String text) {
    setState(() => _popText = text);
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _popText = null);
    });
  }

  Future<void> _feed() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final pet = await ref.read(petRepositoryProvider).feed();
      if (!mounted) return;
      setState(() => _pet = pet);
      _showPop('+2');
    } on FeedCooldownException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Already fed recently — try again later')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pet_() async {
    if (_busy) return;
    setState(() => _busy = true);
    final pet = await ref.read(petRepositoryProvider).petTheCat();
    if (!mounted) return;
    setState(() {
      _pet = pet;
      _busy = false;
    });
    _showPop('♥');
  }

  IconData _moodIcon(MoodState mood) {
    switch (mood) {
      case MoodState.sad:
        return Icons.sentiment_very_dissatisfied;
      case MoodState.content:
        return Icons.sentiment_neutral;
      case MoodState.happy:
        return Icons.sentiment_satisfied;
      case MoodState.ecstatic:
        return Icons.sentiment_very_satisfied;
    }
  }

  // Mood maps onto existing semantic tokens only — no new colors.
  Color _moodTint(GlassTokens t, MoodState mood) {
    switch (mood) {
      case MoodState.sad:
        return t.negative;
      case MoodState.content:
        return t.textSecondary;
      case MoodState.happy:
      case MoodState.ecstatic:
        return t.positive;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final pet = _pet;
    final reduceMotion = motionReduced(context);
    final glowDuration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 400);
    final popDuration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 200);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (pet != null)
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerRight,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_moodIcon(pet.mood), size: 16, color: t.textSecondary),
                  const SizedBox(width: 4),
                  Icon(Icons.paid, size: 14, color: t.textMuted),
                  const SizedBox(width: 2),
                  Text('${pet.coins}',
                      style: TextStyle(color: t.textMuted, fontSize: 12)),
                ],
              ),
              Positioned(
                top: -16,
                child: AnimatedOpacity(
                  opacity: _popText == null ? 0 : 1,
                  duration: popDuration,
                  child: Text(
                    _popText ?? '',
                    style: TextStyle(
                      color: t.positive,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        AnimatedContainer(
          duration: glowDuration,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: pet == null
                ? const []
                : [
                    BoxShadow(
                      color: _moodTint(t, pet.mood).withValues(alpha: 0.25),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
          ),
          child: Image.asset(
            'assets/images/cat.png',
            width: widget.width,
            fit: BoxFit.fitWidth,
            errorBuilder: (context, error, stack) => Container(
              width: widget.width,
              height: widget.width * 0.7,
              decoration: BoxDecoration(
                color: t.textPrimary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(26),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.pets, size: widget.width * 0.22, color: t.textSecondary),
                  const SizedBox(height: 6),
                  Text('cat', style: TextStyle(color: t.textMuted, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
        if (pet != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: 'Feed',
                child: SoftIconButton(
                  icon: Icons.restaurant,
                  onTap: _busy ? () {} : _feed,
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Pet',
                child: SoftIconButton(
                  icon: Icons.front_hand,
                  onTap: _busy ? () {} : _pet_,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
```

- [ ] **Step 3: Update `_BalanceCard` to use the new widget**

In `_BalanceCard` (around line 300), replace `_CatPlaceholder(width: 200)` with `_PetCatWidget(width: 200)`. Delete the now-unused `_CatPlaceholder` class entirely.

- [ ] **Step 4: Manually verify in a running app**

Run: `scripts/run_dev.sh` (per `README.md`), open the home screen. Expected: mood icon + coin count appear above the cat, a soft colored glow appears behind the cat tinted toward green (happy/ecstatic) or muted red (sad), a snackbar shows "Daily check-in: +5 coins" once per day, tapping the feed icon shows a brief "+2" pop and increases the coin count and mood, tapping again within 3 hours shows the cooldown snackbar, tapping the pet icon shows a "♥" pop and bumps mood with no coin change, long-pressing either icon shows its tooltip ("Feed"/"Pet"). With OS-level reduced-motion enabled, the glow and pop appear/disappear instantly with no fade.

- [ ] **Step 5: Commit**

```bash
git add lib/features/home/home_screen.dart
git commit -m "feat: interactive mood-aware pet cat on home screen"
```

---

### Task 8: Activities screen

**Files:**
- Create: `lib/features/pet/activities_screen.dart`
- Modify: `lib/features/home/home_screen.dart` (add navigation entry point)

**Interfaces:**
- Consumes: `petRepositoryProvider`, `Activity`, `PetMemory`, `InsufficientCoinsException` (Tasks 3-4).
- Produces: `ActivitiesScreen` (no-arg `ConsumerWidget` constructor), pushed via `MaterialPageRoute`.

- [ ] **Step 1: Write the screen**

Design notes (see "UI/UX Design Guidelines" above): an activity the user
can't afford is dimmed and its cost pill shows muted colors *before* any tap
— catching `InsufficientCoinsException` is a safety net, not the primary
signal. The activity thumbnail carries a `Hero` tag so tapping through to
the Memory journal (Task 9) that image continues instead of jump-cutting.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/models/activity.dart';
import 'package:meowes_app/models/pet.dart';
import 'package:meowes_app/repositories/pet_repository.dart';

class ActivitiesScreen extends ConsumerStatefulWidget {
  const ActivitiesScreen({super.key});

  @override
  ConsumerState<ActivitiesScreen> createState() => _ActivitiesScreenState();
}

class _ActivitiesScreenState extends ConsumerState<ActivitiesScreen> {
  late Future<List<Activity>> _activitiesFuture;
  int _coins = 0;
  bool _redeeming = false;

  @override
  void initState() {
    super.initState();
    _activitiesFuture = ref.read(petRepositoryProvider).getTodaysActivities();
    _loadCoins();
  }

  Future<void> _loadCoins() async {
    final pet = await ref.read(petRepositoryProvider).getOrCreatePet();
    if (mounted) setState(() => _coins = pet.coins);
  }

  Future<void> _redeem(Activity activity) async {
    if (_redeeming) return;
    setState(() => _redeeming = true);
    try {
      final memory =
          await ref.read(petRepositoryProvider).redeemActivity(activity.id);
      if (!mounted) return;
      setState(() => _coins -= activity.coinCost);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(memory.activityName),
          content: Text(memory.caption),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Nice'),
            ),
          ],
        ),
      );
    } on InsufficientCoinsException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not enough coins for this activity yet')),
      );
    } finally {
      if (mounted) setState(() => _redeeming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;

    return GlassScaffold(
      appBar: GlassAppBar(
        title: 'Activities',
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Text('$_coins coins',
                  style: TextStyle(color: t.textSecondary)),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<Activity>>(
        future: _activitiesFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const SkeletonLoader();
          }
          final activities = snapshot.data!;
          if (activities.isEmpty) {
            return const EmptyStateBox(
              icon: Icons.pets,
              message: 'No activities available right now',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: activities.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final activity = activities[i];
              final affordable = _coins >= activity.coinCost;
              return Opacity(
                opacity: affordable ? 1 : 0.5,
                child: SoftCard(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Hero(
                        tag: 'activity-image-${activity.id}',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            activity.imageAsset,
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stack) => Container(
                              width: 64,
                              height: 64,
                              color: t.textPrimary.withValues(alpha: 0.05),
                              alignment: Alignment.center,
                              child: Icon(Icons.image_outlined, color: t.textMuted),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(activity.name,
                                style: TextStyle(
                                    color: t.textPrimary,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(activity.category,
                                style: TextStyle(color: t.textMuted, fontSize: 12)),
                          ],
                        ),
                      ),
                      PillButton(
                        label: '${activity.coinCost}',
                        primary: affordable,
                        onTap: (_redeeming || !affordable)
                            ? null
                            : () => _redeem(activity),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 2: Add a navigation entry point from the home screen**

In `lib/features/home/home_screen.dart`, near the bell icon's `onTap` (around line 157-159), add a second icon button that pushes `ActivitiesScreen`:

```dart
IconButton(
  icon: const Icon(Icons.pets),
  onPressed: () => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const ActivitiesScreen()),
  ),
),
```

Add the import: `import 'package:meowes_app/features/pet/activities_screen.dart';`

- [ ] **Step 3: Manually verify**

Run: `scripts/run_dev.sh`, tap the new pets icon on home. Expected: today's 3-5 activities appear with images (or the icon fallback, since art assets don't exist yet); activities costing more than your current coin balance appear visibly dimmed with a muted cost pill *before* you tap them; tapping an affordable one shows the caption dialog and decrements the displayed coin count; tapping one you can't afford is a no-op on the dimmed button (the insufficient-coins snackbar is the fallback path, reachable if the balance changes between load and tap).

- [ ] **Step 4: Commit**

```bash
git add lib/features/pet/activities_screen.dart lib/features/home/home_screen.dart
git commit -m "feat: add Activities screen for spending pet coins"
```

---

### Task 9: Memory journal screen

**Files:**
- Create: `lib/features/pet/memory_journal_screen.dart`
- Modify: `lib/features/pet/activities_screen.dart` (add navigation entry point from the app bar)

**Interfaces:**
- Consumes: `petRepositoryProvider`, `PetMemory` (Tasks 3-4).
- Produces: `MemoryJournalScreen` (no-arg `ConsumerWidget` constructor), pushed via `MaterialPageRoute`.

- [ ] **Step 1: Write the screen**

Design notes (see "UI/UX Design Guidelines" above): a single-column
reverse-chronological list, not a grid — this is a diary, not a shop. Each
row gets a `ValueKey` so item state survives rebuilds as new memories are
added, and reuses the `'activity-image-${activityId}'` `Hero` tag from
Task 8 — if the user navigates here right after redeeming (while that
activity is still visible on the Activities screen underneath), the image
continues instead of jump-cutting. If it's not still visible there, the
`Hero` degrades to a normal push with no animation — never a hard failure.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/theme/glass_tokens.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/models/pet_memory.dart';
import 'package:meowes_app/repositories/pet_repository.dart';

class MemoryJournalScreen extends ConsumerWidget {
  const MemoryJournalScreen({super.key});

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    final repo = ref.watch(petRepositoryProvider);

    return GlassScaffold(
      appBar: const GlassAppBar(title: 'Memories'),
      body: FutureBuilder<List<PetMemory>>(
        future: repo.getMemories(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const SkeletonLoader();
          }
          final memories = snapshot.data!;
          if (memories.isEmpty) {
            return const EmptyStateBox(
              icon: Icons.menu_book_outlined,
              message: 'No memories yet — spend coins on an activity to start your journal',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: memories.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final memory = memories[i];
              return SoftCard(
                key: ValueKey(memory.id),
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Hero(
                      tag: 'activity-image-${memory.activityId}',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          memory.imageAsset,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stack) => Container(
                            width: 64,
                            height: 64,
                            color: t.textPrimary.withValues(alpha: 0.05),
                            alignment: Alignment.center,
                            child: Icon(Icons.photo_outlined, color: t.textMuted),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(memory.activityName,
                              style: TextStyle(
                                  color: t.textPrimary,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(memory.caption,
                              style: TextStyle(color: t.textSecondary, fontSize: 13)),
                          const SizedBox(height: 6),
                          Text(_formatDate(memory.completedAt),
                              style: TextStyle(color: t.textMuted, fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 2: Add a navigation entry point from the Activities app bar**

In `lib/features/pet/activities_screen.dart`, add a journal icon to `GlassAppBar`'s `actions` (before the coin count):

```dart
IconButton(
  icon: const Icon(Icons.menu_book_outlined),
  onPressed: () => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const MemoryJournalScreen()),
  ),
),
```

Add the import: `import 'package:meowes_app/features/pet/memory_journal_screen.dart';`

- [ ] **Step 3: Manually verify**

Run: `scripts/run_dev.sh`, redeem an activity from the Activities screen, then tap the journal icon. Expected: the redeemed activity appears at the top of the journal with its caption and today's date; redeeming another activity keeps prior memories, newest first.

- [ ] **Step 4: Commit**

```bash
git add lib/features/pet/memory_journal_screen.dart lib/features/pet/activities_screen.dart
git commit -m "feat: add Memory journal screen"
```
