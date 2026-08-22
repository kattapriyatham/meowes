# Per-food hunger push notifications — design

## Context

Todo item 7 asks for per-food-type custom pet-feeding notifications that
deep-link to the feed screen on tap. Two prior deliberate simplifications
stand in the way and are being reversed by this work:

1. `pets.hungry_notified` is a single boolean and `check_hungry_pets()`
   (`supabase/migrations/20260815150000_push_notifications.sql`) checks one
   "time since any last meal" using `last_fed_at`/`last_fed_food_key`, even
   though each food type has its own independent cooldown clock since
   `supabase/migrations/20260815160000_independent_food_cooldowns.sql`
   (`last_fish_fed_at`, `last_treats_fed_at`, `last_dry_food_fed_at`, each
   gated by its own `food_satiation_hours()`). That migration's comment
   explicitly says hunger notification "reasonably stays" single-model —
   this spec reverses that call.
2. All push notifications deep-link to `ActivityScreen` on tap
   (`_openActivity()` in `lib/main.dart:43-52`), with a comment saying no
   per-notification-type routing is needed. This spec adds a second route
   for `pet_hungry` pushes specifically, to `FeedFlowScreen`.

The single generic "pet is hungry" push is replaced entirely by three
independent per-food pushes — no redundant general notification stays
alongside them.

## DB layer

**Schema** (new migration, e.g.
`supabase/migrations/20260822100000_per_food_hunger_notifications.sql`):

- Add `hungry_notified_fish boolean not null default false`,
  `hungry_notified_treats boolean not null default false`,
  `hungry_notified_dry_food boolean not null default false` to `pets`.
- Drop `hungry_notified`.

**`check_hungry_pets()`** (`create or replace`, still on the existing
15-minute `pg_cron` schedule): loop over pets; for each of the three foods,
independently check
`last_<food>_fed_at is not null and not hungry_notified_<food> and now() > last_<food>_fed_at + (food_satiation_hours('<food>') || ' hours')::interval`.
For each food that's due: set that food's flag `true`, fire one
`net.http_post` to `send-push` with
`{"type": "pet_hungry", "user_id": ..., "food_key": "<food>"}`. A pet can
fire 0–3 pushes in one cron pass (once per due food), matching the
independent-cooldown model already used for feeding itself.

**`feed_pet(p_food_key)`** (`create or replace`, otherwise unchanged from
`supabase/migrations/20260822090000_streak_milestone_notification.sql`):
the `update pets set ...` clears only the fed food's flag —
`hungry_notified_fish = case when p_food_key = 'fish' then false else hungry_notified_fish end`
(and equivalent for treats/dry_food) — leaving the other two foods'
notified state untouched.

## Edge function (`supabase/functions/send-push/index.ts`)

- `Payload`'s `pet_hungry` variant gains a required
  `food_key: 'fish' | 'treats' | 'dry_food'` field.
- `notificationFor()`'s `pet_hungry` branch switches on `food_key`:
  - `fish` → title `"Fish time!"`, body `"<pet name> is ready for fish."`
  - `treats` → title `"Treat time!"`, body `"<pet name> could use a treat."`
  - `dry_food` → title `"Meal time!"`, body `"<pet name> is hungry for dry food."`
  (pet name fetched the same way the existing branch does — fallback
  `"Your cat"` if unset)
- The FCM `data` field (currently `{ type: payload.type }`) extends to
  `{ type: payload.type, ...(payload.type === "pet_hungry" ? { food_key: payload.food_key } : {}) }`
  — this is what the client reads on tap to route and highlight.

## Client (Flutter)

**`lib/core/push_notifications.dart`:**

- `showForegroundNotification` passes
  `payload: jsonEncode(message.data)` to `localNotificationsPlugin.show()`.
- `initLocalNotifications`'s `onTap` parameter changes from
  `void Function()` to `void Function(Map<String, String> data)`. Inside
  `onDidReceiveNotificationResponse`, decode `response.payload` via
  `jsonDecode` into `Map<String, String>` (empty map if null or decode
  fails) and pass it to `onTap`.

**`lib/main.dart`:**

- Replace the no-arg `_openActivity()` callback wiring with a single
  shared handler, `_handleNotificationTap(Map<String, String> data)`, used
  for all three tap paths: the local-notification `onTap`,
  `FirebaseMessaging.onMessageOpenedApp`, and
  `FirebaseMessaging.instance.getInitialMessage()` (the latter two already
  hand over a `RemoteMessage` — pass `message.data`).
- `_handleNotificationTap`: if `data['type'] == 'pet_hungry'`, call
  `_openFeedFlow(data['food_key'])`; otherwise call the existing
  `_openActivity()` unchanged.
- New `_openFeedFlow(String? foodKey)`: pushes a new
  `PetFeedDeepLinkScreen` (`ConsumerWidget`) onto `rootNavigatorKey`. It
  fetches the pet via the existing `petRepositoryProvider.getOrCreatePet()`
  (the same call `todaysPetEventsProvider` in `activity_screen.dart`
  already uses), shows a loading spinner while in flight, then replaces
  itself (`Navigator.pushReplacement`) with
  `FeedFlowScreen(pet: pet, highlightFood: parseFoodType(foodKey))`.
  This loader screen exists because `FeedFlowScreen` requires an
  already-loaded `Pet`, and `main.dart`'s tap handlers run outside the
  widget tree with no `ref` available — `_openActivity()` avoids this
  problem because `ActivityScreen` loads its own data internally.

**`lib/features/pet/feed_flow_screen.dart`:**

- `FeedFlowScreen` gains an optional `FoodType? highlightFood` constructor
  param.
- When set, that food's drag icon gets a pulsing outline. Implementation
  reuses the existing `Timer.periodic` (already ticking every 30s for the
  cooldown countdown) or a lightweight `AnimatedContainer`/`TweenAnimationBuilder`
  loop scoped to just that icon — no new heavyweight animation
  infrastructure.
- No auto-drag, no auto-feed. The highlight is purely visual; the user
  still performs the drag themselves.

## Out of scope

- iOS push (already blocked on Apple Developer account / APNs key per
  the top of `todo.md` — unaffected by this change, same guard stays).
- Any change to `expense_split`, `friend_remind`, or `streak_milestone`
  push types — these keep routing to `ActivityScreen` on tap.
- Auto-triggering a feed action from the notification itself.
