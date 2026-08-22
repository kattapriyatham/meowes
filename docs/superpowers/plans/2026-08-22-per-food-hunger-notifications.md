# Per-Food Hunger Push Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single "pet is hungry" push with three independent per-food-type pushes (fish/treats/dry_food), and make tapping one deep-link straight to the feed screen with that food highlighted, instead of the generic Activity screen.

**Architecture:** DB layer tracks hunger-notified state per food type (three booleans instead of one) and fires one push per food independently from the existing 15-minute cron. The edge function gains food-specific copy and threads a `food_key` through the FCM data payload. The Flutter client decodes that payload on tap and routes `pet_hungry` notifications to a new lightweight loader screen that fetches the pet then opens the feed screen with the named food highlighted; every other notification type keeps routing to Activity as before.

**Tech Stack:** Supabase Postgres (plpgsql, pg_cron, pg_net), Deno edge function (TypeScript), Flutter (Riverpod, firebase_messaging, flutter_local_notifications).

**Spec:** [docs/superpowers/specs/2026-08-22-per-food-hunger-notifications-design.md](../specs/2026-08-22-per-food-hunger-notifications-design.md)

## Global Constraints

- Notification copy is fixed (from the spec): fish → "Fish time!" / "<pet> is ready for fish."; treats → "Treat time!" / "<pet> could use a treat."; dry_food → "Meal time!" / "<pet> is hungry for dry food."
- The single generic "pet is hungry" push is removed entirely — no fallback general notification stays alongside the three per-food ones.
- `expense_split`, `friend_remind`, and `streak_milestone` pushes are unaffected and keep routing to `ActivityScreen` on tap.
- No local Supabase/Docker is running in this environment (confirmed this session) — DB and edge-function changes are verified by applying them to the linked remote project (`supabase db push` / `supabase functions deploy`) rather than an automated local test suite, matching how every other migration in this repo (including the streak-milestone one from earlier this session) has been verified. Flutter-side pure logic gets real `flutter test` coverage; there is no existing precedent for widget tests on pet screens in this repo (checked — none exist), so the new/changed screens are verified via `flutter analyze` and manual run instead of new widget-test infrastructure.
- Project ref for all `supabase` CLI commands: already linked (`pacbkvuepitmmqxudscx`, confirmed active this session) — no `--project-ref` flag needed.

---

### Task 1: DB — per-food hunger schema, cron, and feed_pet update

**Files:**
- Create: `supabase/migrations/20260822100000_per_food_hunger_notifications.sql`

**Interfaces:**
- Consumes: existing `pets` columns `last_fish_fed_at`, `last_treats_fed_at`, `last_dry_food_fed_at` (from `supabase/migrations/20260815160000_independent_food_cooldowns.sql`), existing `food_satiation_hours(p_food_key text) returns integer` (from `supabase/migrations/20260815110000_food_satiation_and_hunger_decay.sql`), existing `net.http_post` push pattern (from `supabase/migrations/20260815150000_push_notifications.sql`).
- Produces: `pets.hungry_notified_fish`, `pets.hungry_notified_treats`, `pets.hungry_notified_dry_food` (booleans, replacing the dropped `pets.hungry_notified`); `check_hungry_pets()` now sends `{"type": "pet_hungry", "user_id": ..., "food_key": "fish"|"treats"|"dry_food"}` payloads (consumed by Task 2's edge function); `feed_pet(p_food_key text) returns pets` keeps its existing signature and streak-milestone push block from `supabase/migrations/20260822090000_streak_milestone_notification.sql`, only the hunger-flag-clearing logic changes.

- [ ] **Step 1: Write the migration file**

```sql
-- Reverses the "single hunger model" call in
-- 20260815160000_independent_food_cooldowns.sql: each food type now
-- tracks its own hungry_notified state and fires its own push
-- independently, since each already has its own cooldown clock
-- (last_fish_fed_at/last_treats_fed_at/last_dry_food_fed_at). A pet can
-- fire 0-3 pushes in one cron pass now, one per food that's due.
alter table pets add column hungry_notified_fish boolean not null default false;
alter table pets add column hungry_notified_treats boolean not null default false;
alter table pets add column hungry_notified_dry_food boolean not null default false;

create or replace function check_hungry_pets()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
begin
  for r in
    select user_id
    from pets
    where last_fish_fed_at is not null
      and not hungry_notified_fish
      and now() > last_fish_fed_at + (food_satiation_hours('fish') || ' hours')::interval
  loop
    update pets set hungry_notified_fish = true where user_id = r.user_id;
    perform net.http_post(
      url := 'https://pacbkvuepitmmqxudscx.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBhY2JrdnVlcGl0bW1xeHVkc2N4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODUxNTM4NjEsImV4cCI6MjEwMDcyOTg2MX0.UTgVDAD_dMtGVjANU5_Gssv9E9fnaJ0AP22-h4x8leE'
      ),
      body := jsonb_build_object('type', 'pet_hungry', 'user_id', r.user_id, 'food_key', 'fish')
    );
  end loop;

  for r in
    select user_id
    from pets
    where last_treats_fed_at is not null
      and not hungry_notified_treats
      and now() > last_treats_fed_at + (food_satiation_hours('treats') || ' hours')::interval
  loop
    update pets set hungry_notified_treats = true where user_id = r.user_id;
    perform net.http_post(
      url := 'https://pacbkvuepitmmqxudscx.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBhY2JrdnVlcGl0bW1xeHVkc2N4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODUxNTM4NjEsImV4cCI6MjEwMDcyOTg2MX0.UTgVDAD_dMtGVjANU5_Gssv9E9fnaJ0AP22-h4x8leE'
      ),
      body := jsonb_build_object('type', 'pet_hungry', 'user_id', r.user_id, 'food_key', 'treats')
    );
  end loop;

  for r in
    select user_id
    from pets
    where last_dry_food_fed_at is not null
      and not hungry_notified_dry_food
      and now() > last_dry_food_fed_at + (food_satiation_hours('dry_food') || ' hours')::interval
  loop
    update pets set hungry_notified_dry_food = true where user_id = r.user_id;
    perform net.http_post(
      url := 'https://pacbkvuepitmmqxudscx.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBhY2JrdnVlcGl0bW1xeHVkc2N4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODUxNTM4NjEsImV4cCI6MjEwMDcyOTg2MX0.UTgVDAD_dMtGVjANU5_Gssv9E9fnaJ0AP22-h4x8leE'
      ),
      body := jsonb_build_object('type', 'pet_hungry', 'user_id', r.user_id, 'food_key', 'dry_food')
    );
  end loop;
end;
$$;
revoke all on function check_hungry_pets() from public;

-- feed_pet() is unchanged except for how it clears hunger-notified state:
-- only the food actually fed gets its flag cleared, the other two foods'
-- notified state is untouched (each food's hunger is independent now).
create or replace function feed_pet(p_food_key text default 'dry_food')
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
  v_base_reward integer;
  v_cooldown_hours integer;
  v_last_fed_this_food timestamptz;
begin
  perform get_or_create_pet();

  select * into v_pet from pets where user_id = auth.uid() for update;

  v_cooldown_hours := food_satiation_hours(p_food_key);
  v_last_fed_this_food := case p_food_key
    when 'fish' then v_pet.last_fish_fed_at
    when 'treats' then v_pet.last_treats_fed_at
    when 'dry_food' then v_pet.last_dry_food_fed_at
    else null
  end;

  if v_last_fed_this_food is not null
      and v_last_fed_this_food > now() - (v_cooldown_hours || ' hours')::interval then
    raise exception 'feed_cooldown';
  end if;

  v_base_reward := case p_food_key
    when 'fish' then 3
    when 'treats' then 2
    when 'dry_food' then 2
    else 2
  end;

  if v_pet.last_feed_streak_date = v_today - 1 then
    v_streak := v_pet.feed_streak_days + 1;
  elsif v_pet.last_feed_streak_date = v_today then
    v_streak := v_pet.feed_streak_days;
  else
    v_streak := 1;
  end if;

  v_bonus := case when v_streak = 7 then 10 else 0 end;

  update pets
  set coins = coins + v_base_reward + v_bonus,
      mood_score = least(mood_score + 10, 100),
      last_fed_at = now(),
      last_fed_food_key = p_food_key,
      last_fish_fed_at = case when p_food_key = 'fish' then now() else last_fish_fed_at end,
      last_treats_fed_at = case when p_food_key = 'treats' then now() else last_treats_fed_at end,
      last_dry_food_fed_at = case when p_food_key = 'dry_food' then now() else last_dry_food_fed_at end,
      last_hunger_decay_at = now(),
      hungry_notified_fish = case when p_food_key = 'fish' then false else hungry_notified_fish end,
      hungry_notified_treats = case when p_food_key = 'treats' then false else hungry_notified_treats end,
      hungry_notified_dry_food = case when p_food_key = 'dry_food' then false else hungry_notified_dry_food end,
      last_care_at = now(),
      feed_streak_days = case when v_streak = 7 then 0 else v_streak end,
      last_feed_streak_date = v_today
  where user_id = auth.uid()
  returning * into v_pet;

  if v_streak = 7 then
    perform net.http_post(
      url := 'https://pacbkvuepitmmqxudscx.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBhY2JrdnVlcGl0bW1xeHVkc2N4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODUxNTM4NjEsImV4cCI6MjEwMDcyOTg2MX0.UTgVDAD_dMtGVjANU5_Gssv9E9fnaJ0AP22-h4x8leE'
      ),
      body := jsonb_build_object('type', 'streak_milestone', 'user_id', auth.uid(), 'streak_days', 7)
    );
  end if;

  return v_pet;
end;
$$;
revoke all on function feed_pet(text) from public;
grant execute on function feed_pet(text) to authenticated;

-- The old single-hunger-model column is fully superseded by the three
-- above; drop it last (function bodies above no longer reference it).
alter table pets drop column hungry_notified;
```

- [ ] **Step 2: Apply to the linked remote project**

Run: `supabase db push`
Expected: prompts to confirm, then `Applying migration 20260822100000_per_food_hunger_notifications.sql...` followed by `Finished supabase db push.` with no errors. (The `Docker daemon` cache warning that appears is unrelated and safe to ignore — confirmed this session.)

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260822100000_per_food_hunger_notifications.sql
git commit -m "feat: track pet hunger notifications independently per food type

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: Edge function — food-specific pet_hungry payload and copy

**Files:**
- Modify: `supabase/functions/send-push/index.ts`

**Interfaces:**
- Consumes: `{"type": "pet_hungry", "user_id": ..., "food_key": "fish"|"treats"|"dry_food"}` payloads sent by Task 1's `check_hungry_pets()`.
- Produces: FCM message with per-food `notification.title`/`notification.body`, and `data.food_key` alongside the existing `data.type` — consumed by Task 4/6's client-side tap routing.

- [ ] **Step 1: Extend the `Payload` union**

In `supabase/functions/send-push/index.ts`, change:

```typescript
type Payload =
  | { type: "expense_split"; expense_id: string; user_id: string }
  | { type: "pet_hungry"; user_id: string }
  | { type: "friend_remind"; user_id: string; reminder_user_id: string; amount: number; pet_name: string }
  | { type: "streak_milestone"; user_id: string; streak_days: number };
```

to:

```typescript
type Payload =
  | { type: "expense_split"; expense_id: string; user_id: string }
  | { type: "pet_hungry"; user_id: string; food_key: "fish" | "treats" | "dry_food" }
  | { type: "friend_remind"; user_id: string; reminder_user_id: string; amount: number; pet_name: string }
  | { type: "streak_milestone"; user_id: string; streak_days: number };
```

- [ ] **Step 2: Replace the generic pet_hungry fallback with per-food copy**

Find the tail of `notificationFor()` — currently:

```typescript
  const { data: pet } = await admin
    .from("pets")
    .select("name")
    .eq("user_id", payload.user_id)
    .maybeSingle();
  return {
    title: `${pet?.name ?? "Your cat"} is hungry`,
    body: "Time for a meal — tap to feed your cat.",
  };
}
```

Replace it with:

```typescript
  const petHungryCopy: Record<"fish" | "treats" | "dry_food", { title: string; body: (name: string) => string }> = {
    fish: { title: "Fish time!", body: (name) => `${name} is ready for fish.` },
    treats: { title: "Treat time!", body: (name) => `${name} could use a treat.` },
    dry_food: { title: "Meal time!", body: (name) => `${name} is hungry for dry food.` },
  };

  const { data: pet } = await admin
    .from("pets")
    .select("name")
    .eq("user_id", payload.user_id)
    .maybeSingle();
  const copy = petHungryCopy[payload.food_key];
  return { title: copy.title, body: copy.body(pet?.name ?? "Your cat") };
}
```

(TypeScript narrows `payload` to the `pet_hungry` variant here because every earlier branch in the function returns — same as the existing `streak_milestone` branch above it.)

- [ ] **Step 3: Thread `food_key` into the FCM data payload**

Find, inside `Deno.serve`:

```typescript
          body: JSON.stringify({
            message: {
              token,
              notification,
              data: { type: payload.type },
            },
          }),
```

Replace with:

```typescript
          body: JSON.stringify({
            message: {
              token,
              notification,
              data: {
                type: payload.type,
                ...(payload.type === "pet_hungry" ? { food_key: payload.food_key } : {}),
              },
            },
          }),
```

- [ ] **Step 4: Deploy and verify**

Run: `supabase functions deploy send-push`
Expected: `{"project_ref":"pacbkvuepitmmqxudscx","functions":["send-push"],"dashboard_url":"...","message":"Deployed Functions."}` with no errors (the CLI bundles and typechecks the TypeScript as part of the upload — a syntax or type error here fails the deploy, so a clean deploy is the verification).

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/send-push/index.ts
git commit -m "feat: send food-specific copy for pet-hungry push notifications

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: `foodTypeFromKey` helper

**Files:**
- Modify: `lib/models/food.dart`
- Test: `test/models/food_test.dart` (new)

**Interfaces:**
- Consumes: existing `FoodType` enum and its `.key` getter (`lib/models/food.dart`).
- Produces: `FoodType? foodTypeFromKey(String? key)` — top-level function, consumed by Task 5 (`PetFeedDeepLinkScreen`).

- [ ] **Step 1: Write the failing test**

Create `test/models/food_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowes_app/models/food.dart';

void main() {
  group('foodTypeFromKey', () {
    test('parses each valid key back to its FoodType', () {
      expect(foodTypeFromKey('fish'), FoodType.fish);
      expect(foodTypeFromKey('treats'), FoodType.treats);
      expect(foodTypeFromKey('dry_food'), FoodType.dryFood);
    });

    test('returns null for an unknown or missing key', () {
      expect(foodTypeFromKey('not_a_food'), isNull);
      expect(foodTypeFromKey(null), isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/food_test.dart`
Expected: FAIL — `foodTypeFromKey` isn't defined.

- [ ] **Step 3: Implement**

In `lib/models/food.dart`, add after the `FoodTypeInfo` extension:

```dart
/// Inverse of [FoodTypeInfo.key] — used to route a push notification's
/// `food_key` data field back to a [FoodType] (see
/// `PetFeedDeepLinkScreen`). Returns null for an unrecognized or missing
/// key rather than throwing, since it's fed untrusted push-payload data.
FoodType? foodTypeFromKey(String? key) {
  for (final food in FoodType.values) {
    if (food.key == key) return food;
  }
  return null;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/food_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/models/food.dart test/models/food_test.dart
git commit -m "feat: add foodTypeFromKey helper for notification deep-linking

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: Thread notification payload data through local notifications

**Files:**
- Modify: `lib/core/push_notifications.dart`
- Test: `test/core/push_notifications_test.dart` (new)

**Interfaces:**
- Consumes: nothing new.
- Produces: `Map<String, String> decodeNotificationPayload(String? raw)` (pure function); `initLocalNotifications({required void Function(Map<String, String> data) onTap})` — signature changed from `void Function()` to `void Function(Map<String, String> data)`, consumed by Task 6 (`main.dart`).

- [ ] **Step 1: Write the failing test**

Create `test/core/push_notifications_test.dart`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/push_notifications_test.dart`
Expected: FAIL — `decodeNotificationPayload` isn't defined.

- [ ] **Step 3: Implement**

In `lib/core/push_notifications.dart`, add `import 'dart:convert';` at the top, then add this function (anywhere at top level, e.g. right after the imports):

```dart
/// Decodes the JSON payload string attached to a local notification (set
/// in [showForegroundNotification]) back into the string map used for
/// tap routing. Never throws — a malformed or missing payload just means
/// no routing data, not a crash on tap.
Map<String, String> decodeNotificationPayload(String? raw) {
  if (raw == null) return {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value.toString()));
    }
  } catch (_) {
    // Fall through to the empty-map return below.
  }
  return {};
}
```

Then change `initLocalNotifications`'s signature and body from:

```dart
Future<void> initLocalNotifications({required void Function() onTap}) async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings();
  await localNotificationsPlugin.initialize(
    settings: const InitializationSettings(android: androidInit, iOS: iosInit),
    onDidReceiveNotificationResponse: (_) => onTap(),
  );
```

to:

```dart
Future<void> initLocalNotifications({
  required void Function(Map<String, String> data) onTap,
}) async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings();
  await localNotificationsPlugin.initialize(
    settings: const InitializationSettings(android: androidInit, iOS: iosInit),
    onDidReceiveNotificationResponse: (response) => onTap(decodeNotificationPayload(response.payload)),
  );
```

Then change `showForegroundNotification` from:

```dart
void showForegroundNotification(RemoteMessage message) {
  final notification = message.notification;
  if (notification == null) return;
  localNotificationsPlugin.show(
    id: notification.hashCode,
    title: notification.title,
    body: notification.body,
    notificationDetails: NotificationDetails(
```

to:

```dart
void showForegroundNotification(RemoteMessage message) {
  final notification = message.notification;
  if (notification == null) return;
  localNotificationsPlugin.show(
    id: notification.hashCode,
    title: notification.title,
    body: notification.body,
    payload: jsonEncode(message.data),
    notificationDetails: NotificationDetails(
```

(leave the rest of `showForegroundNotification` — the `NotificationDetails(...)` block and its closing — unchanged).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/push_notifications_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Run full analyzer to confirm the signature change has no other call sites yet**

Run: `flutter analyze lib/core/push_notifications.dart`
Expected: this file analyzes clean. (`lib/main.dart` will show an error here — `initLocalNotifications(onTap: _openActivity)` no longer matches the new signature — that's expected and fixed in Task 6; don't fix it in this task.)

- [ ] **Step 6: Commit**

```bash
git add lib/core/push_notifications.dart test/core/push_notifications_test.dart
git commit -m "feat: thread notification data payload through local-notification taps

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: `PetFeedDeepLinkScreen`

**Files:**
- Create: `lib/features/pet/pet_feed_deep_link_screen.dart`

**Interfaces:**
- Consumes: `petRepositoryProvider.getOrCreatePet()` (`lib/repositories/pet_repository.dart`, unchanged), `foodTypeFromKey` (Task 3), `FeedFlowScreen(pet: Pet, highlightFood: FoodType?)` (Task 7 adds `highlightFood` — this task can be written and reviewed now referencing the param name/type from the spec; Task 7 must land before this compiles against the real signature. If executing tasks out of order, land Task 7 first or stub the param.)
- Produces: `PetFeedDeepLinkScreen({String? foodKey})` widget, consumed by Task 6 (`main.dart`).

- [ ] **Step 1: Write the screen**

Create `lib/features/pet/pet_feed_deep_link_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/pet/feed_flow_screen.dart';
import 'package:meowes_app/models/food.dart';
import 'package:meowes_app/repositories/pet_repository.dart';

/// Pushed when a `pet_hungry` push notification is tapped (see
/// `_openFeedFlow` in `lib/main.dart`). `FeedFlowScreen` needs an
/// already-loaded `Pet`, but the tap handler runs outside the widget
/// tree with no `ref` available to fetch one — this screen bridges that
/// gap with a brief loading spinner, then replaces itself with the real
/// feed screen, food highlighted.
class PetFeedDeepLinkScreen extends ConsumerStatefulWidget {
  const PetFeedDeepLinkScreen({super.key, this.foodKey});
  final String? foodKey;

  @override
  ConsumerState<PetFeedDeepLinkScreen> createState() => _PetFeedDeepLinkScreenState();
}

class _PetFeedDeepLinkScreenState extends ConsumerState<PetFeedDeepLinkScreen> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pet = await ref.read(petRepositoryProvider).getOrCreatePet();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => FeedFlowScreen(pet: pet, highlightFood: foodTypeFromKey(widget.foodKey)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const GlassScaffold(body: Center(child: CircularProgressIndicator()));
  }
}
```

- [ ] **Step 2: Confirm it doesn't compile standalone yet (expected)**

Run: `flutter analyze lib/features/pet/pet_feed_deep_link_screen.dart`
Expected: an error that `FeedFlowScreen` has no `highlightFood` parameter — expected until Task 7 lands. If Task 7 is already done, expect no errors instead.

- [ ] **Step 3: Commit**

```bash
git add lib/features/pet/pet_feed_deep_link_screen.dart
git commit -m "feat: add PetFeedDeepLinkScreen to load pet before opening feed flow

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: `main.dart` — shared notification tap routing

**Files:**
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: `initLocalNotifications({required void Function(Map<String, String> data) onTap})` (Task 4), `PetFeedDeepLinkScreen({String? foodKey})` (Task 5).
- Produces: nothing new consumed elsewhere — this is the top of the call chain.

- [ ] **Step 1: Add the import**

In `lib/main.dart`, add alongside the other `features/` imports:

```dart
import 'package:meowes_app/features/pet/pet_feed_deep_link_screen.dart';
```

- [ ] **Step 2: Replace `_openActivity` wiring with a shared tap handler**

Find:

```dart
/// Where every push notification leads on tap — both event kinds (expense
/// splits, pet hunger) already show up in the Activity feed, so there's no
/// need for per-notification-type routing. Top-level rather than a State
/// method: [initLocalNotifications] is called from `main()`, before any
/// [_MeowesAppState] instance exists.
void _openActivity() {
  rootNavigatorKey.currentState?.push(
    MaterialPageRoute(builder: (_) => const ActivityScreen()),
  );
}
```

Replace with:

```dart
/// Where every push notification leads on tap. Most event kinds (expense
/// splits, streak milestones, friend reminders) already show up in the
/// Activity feed, so they route there. `pet_hungry` pushes carry a
/// `food_key` in their data payload and route straight to the feed
/// screen instead, with that food highlighted. Top-level rather than a
/// State method: [initLocalNotifications] is called from `main()`,
/// before any [_MeowesAppState] instance exists.
void _handleNotificationTap(Map<String, String> data) {
  if (data['type'] == 'pet_hungry') {
    _openFeedFlow(data['food_key']);
    return;
  }
  _openActivity();
}

void _openActivity() {
  rootNavigatorKey.currentState?.push(
    MaterialPageRoute(builder: (_) => const ActivityScreen()),
  );
}

void _openFeedFlow(String? foodKey) {
  rootNavigatorKey.currentState?.push(
    MaterialPageRoute(builder: (_) => PetFeedDeepLinkScreen(foodKey: foodKey)),
  );
}
```

- [ ] **Step 3: Wire the new handler into all three tap paths**

Find, in `main()`:

```dart
  await initLocalNotifications(onTap: _openActivity);
```

Replace with:

```dart
  await initLocalNotifications(onTap: _handleNotificationTap);
```

Find, in `_MeowesAppState.initState()`:

```dart
    _foregroundMessageSub = FirebaseMessaging.onMessage.listen(showForegroundNotification);
    _messageTapSub = FirebaseMessaging.onMessageOpenedApp.listen((_) => _openActivity());
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) _openActivity();
    });
```

Replace with:

```dart
    _foregroundMessageSub = FirebaseMessaging.onMessage.listen(showForegroundNotification);
    _messageTapSub = FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _handleNotificationTap(Map<String, String>.from(message.data)),
    );
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) _handleNotificationTap(Map<String, String>.from(message.data));
    });
```

- [ ] **Step 4: Analyze**

Run: `flutter analyze lib/main.dart lib/core/push_notifications.dart lib/features/pet/pet_feed_deep_link_screen.dart`
Expected: clean (assuming Task 7 has landed so `FeedFlowScreen(highlightFood: ...)` resolves — if not, run this again after Task 7).

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart
git commit -m "feat: route pet-hungry push taps to the feed screen instead of Activity

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 7: `FeedFlowScreen` — `highlightFood` pulsing highlight

**Files:**
- Modify: `lib/features/pet/feed_flow_screen.dart`

**Interfaces:**
- Consumes: `FoodType` (`lib/models/food.dart`, unchanged).
- Produces: `FeedFlowScreen({required Pet pet, FoodType? highlightFood})` — the `highlightFood` param consumed by Task 5 (`PetFeedDeepLinkScreen`).

- [ ] **Step 1: Add the `highlightFood` param to `FeedFlowScreen`**

Find:

```dart
class FeedFlowScreen extends ConsumerStatefulWidget {
  const FeedFlowScreen({super.key, required this.pet});
  final Pet pet;
```

Replace with:

```dart
class FeedFlowScreen extends ConsumerStatefulWidget {
  const FeedFlowScreen({super.key, required this.pet, this.highlightFood});
  final Pet pet;

  /// Set when this screen was opened from a pet-hungry push notification
  /// (see `PetFeedDeepLinkScreen`) — pulses an outline around this food's
  /// bowl so the user can see at a glance which one the notification was
  /// about. Purely visual: the user still has to drag it themselves.
  final FoodType? highlightFood;
```

- [ ] **Step 2: Pass `highlightFood` down to each regular bowl**

Find, inside the `build` method's `FutureBuilder` for the bottom bowl row:

```dart
                              final regularBowls = FoodType.values
                                  .where((f) => _remainingFor(f) == null)
                                  .map((f) => _DraggableFoodBowl(
                                        food: f,
                                        enabled: !_eating && _remainingFor(f) == null,
                                        remaining: _remainingFor(f),
                                      ))
                                  .toList();
```

Replace with:

```dart
                              final regularBowls = FoodType.values
                                  .where((f) => _remainingFor(f) == null)
                                  .map((f) => _DraggableFoodBowl(
                                        food: f,
                                        enabled: !_eating && _remainingFor(f) == null,
                                        remaining: _remainingFor(f),
                                        highlighted: f == widget.highlightFood,
                                      ))
                                  .toList();
```

- [ ] **Step 3: Add the `highlighted` param to `_DraggableFoodBowl` and use it**

Find:

```dart
class _DraggableFoodBowl extends StatelessWidget {
  final FoodType food;
  final bool enabled;

  /// Time left until this specific food is available again, or null when
  /// it can be fed now — each food cools down independently, so this
  /// differs per bowl. Shown as a countdown chip in place of the
  /// coin-reward badge while on cooldown.
  final Duration? remaining;

  const _DraggableFoodBowl({
    required this.food,
    required this.enabled,
    this.remaining,
  });
```

Replace with:

```dart
class _DraggableFoodBowl extends StatelessWidget {
  final FoodType food;
  final bool enabled;

  /// Time left until this specific food is available again, or null when
  /// it can be fed now — each food cools down independently, so this
  /// differs per bowl. Shown as a countdown chip in place of the
  /// coin-reward badge while on cooldown.
  final Duration? remaining;

  /// True when a pet-hungry push notification named this food — draws a
  /// pulsing highlight around its bowl (see [_PulsingHighlight]).
  final bool highlighted;

  const _DraggableFoodBowl({
    required this.food,
    required this.enabled,
    this.remaining,
    this.highlighted = false,
  });
```

Find, inside `_DraggableFoodBowl.build`:

```dart
    final bowl = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BowlImage(food: food, size: 52),
        const SizedBox(height: 4),
```

Replace with:

```dart
    final bowlImage = _BowlImage(food: food, size: 52);
    final bowl = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        highlighted ? _PulsingHighlight(child: bowlImage) : bowlImage,
        const SizedBox(height: 4),
```

- [ ] **Step 4: Add the `_PulsingHighlight` widget**

Add this new class anywhere at file scope, e.g. right after the `_DraggableFoodBowl` class closes (before `_DraggableSpecialBowl`):

```dart
/// Wraps a bowl image with a slow, repeating glow ring — draws attention
/// to the food a tapped pet-hungry notification named. Purely visual: it
/// doesn't drag or feed anything on the user's behalf.
class _PulsingHighlight extends StatefulWidget {
  final Widget child;
  const _PulsingHighlight({required this.child});

  @override
  State<_PulsingHighlight> createState() => _PulsingHighlightState();
}

class _PulsingHighlightState extends State<_PulsingHighlight> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GlassTokens>()!;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: t.positive.withValues(alpha: 0.25 + _controller.value * 0.35),
              blurRadius: 8 + _controller.value * 6,
              spreadRadius: 1 + _controller.value * 2,
            ),
          ],
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}
```

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/features/pet/feed_flow_screen.dart`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add lib/features/pet/feed_flow_screen.dart
git commit -m "feat: highlight the notified food when FeedFlowScreen opens from a push

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 8: Full-project verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full analyzer**

Run: `flutter analyze`
Expected: no new errors or warnings beyond whatever pre-existing ones the project already had before this plan (compare against a baseline run before Task 1 if unsure).

- [ ] **Step 2: Run the full test suite**

Run: `flutter test`
Expected: all tests pass, including the new `test/models/food_test.dart` and `test/core/push_notifications_test.dart`.

- [ ] **Step 3: Manual smoke check (no automated coverage exists for this path)**

With the app running against the linked Supabase project (already has both migrations pushed and the edge function deployed from Tasks 1–2): let a pet go past a food's satiation window, wait for/trigger `check_hungry_pets()` (or invoke it directly via the Supabase SQL editor with `select check_hungry_pets();` for an immediate check instead of waiting up to 15 minutes), confirm the push arrives with food-specific copy, and confirm tapping it opens `FeedFlowScreen` with that food's bowl pulsing.

- [ ] **Step 4: Update `todo.md`**

In `todo.md`, find:

```
- **Customize pet feeding notifications per food item** — Each food type
  (fish, treats, dry food) should have custom notifications. On click,
  redirect to pet feeding screen (`lib/features/notifications/notifications_screen.dart`).
```

Replace with:

```
- ~~**Customize pet feeding notifications per food item**~~ ✅ **DONE** — Each
  food type fires its own hunger push independently (`hungry_notified_fish`/
  `_treats`/`_dry_food` on `pets`, `check_hungry_pets()` in
  `supabase/migrations/20260822100000_per_food_hunger_notifications.sql`), with
  food-specific copy (`supabase/functions/send-push/index.ts`) and a tap
  routes straight to `FeedFlowScreen` with that food highlighted
  (`lib/main.dart`, `lib/features/pet/pet_feed_deep_link_screen.dart`,
  `lib/features/pet/feed_flow_screen.dart`).
```

- [ ] **Step 5: Commit**

```bash
git add todo.md
git commit -m "docs: mark per-food feeding notifications todo item done

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```
