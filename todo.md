# Todo

- **iOS push notifications** — Real push (FCM) is live and verified on
  Android: expense-involvement + pet-hunger pushes, via `pg_net`/`pg_cron`
  triggers → `send-push` Edge Function (`supabase/functions/send-push`) →
  FCM. iOS needs an Apple Developer account + APNs auth key uploaded to
  Firebase, then `GoogleService-Info.plist` added to the Xcode project and
  `Firebase.initializeApp()` wired for iOS in `lib/main.dart`.

- ~~**Streak-milestone push notification**~~ ✅ **DONE** — 7-day feed streak
  fires `streak_milestone` push from `feed_pet()`, same
  `net.http_post`-to-`send-push` pattern as `check_hungry_pets()`
  (`supabase/migrations/20260822090000_streak_milestone_notification.sql`,
  `supabase/functions/send-push/index.ts`).

- **"Friend fed your pet" push** — split out from the streak-milestone item.
  No underlying feature exists yet: `feed_pet()` only feeds the caller's own
  pet, there's no RPC letting one user feed a friend's pet. Needs product
  design first (gift food? feed on their behalf?) before any schema/RPC work.

- ~~**Bottom dock missing right after signup** — `ProfileSetupScreen` navigates
  to the bare `HomeScreen` after account creation, not `HomeShell`, so the
  dock (Home/Pet/Friends/Groups/Activity/Profile) is absent until the next
  cold app launch, at which point `RootScreen` correctly routes to
  `HomeShell` since a `users` row now exists. Fix: have `ProfileSetupScreen`
  navigate to `HomeShell` instead of `HomeScreen` (`lib/features/root/root_screen.dart`,
  `lib/features/auth/profile_setup_screen.dart`).~~ ✅ **DONE** — Already navigates to `HomeShell`.

- ~~**Gray container bug in add expense** — When all options deselected in "who's
  sharing" section, shows gray container. Should either prevent deselecting all
  or hide container (`lib/features/expenses/add_expense_screen.dart`).~~ ✅ **DONE** — Prevent deselecting last person; "Clear" becomes "keep at least one".

- ~~**Fix pet-feeding methodology** — Define TTL/satiation duration per food type~~ ✅ **DONE** — Per-food satiation implemented (Fish: 6h, Dry Food: 4h, Treats: 12h). Hunger decay system active. Independent cooldowns per food type.

- ~~**Add pet naming/customization feature** — Allow user to set/edit pet's name.
  Likely in pet profile screen or first-time setup.~~ ✅ **DONE** — `_PetNameCard` in `profile_screen.dart` opens dialog, saves via `petRepository.updateName()`.

- **Implement invite link feature to add friends** — Allow users to generate
  and share invite links. Other users can join via link
  (`lib/features/friends/friends_screen.dart`).

- **Implement notification system** — Notify users when involved in expense.
  Also explore pet feeding notifications (hungry, friend fed pet, streak
  milestones) (`lib/features/notifications/notifications_screen.dart`).

- **Add daily checkin system** — Show toast notification with daily checkin
  coins on first app open each day. Integrate into notifications system
  (`lib/features/home/home_screen.dart`,
  `lib/features/notifications/notifications_screen.dart`).

- ~~**Populate Activity screen with app and pet events** — Show expense events
  (added, settled) and pet activities (purchased with coins) in Activity
  screen. Unified activity log (`lib/features/activity/activity_screen.dart`).~~ ✅ **DONE** — `get_my_activity_feed()` RPC returns expenses, settlements, pet_memories (coin spending). UI renders all three.

- ~~**Check iOS build** — Verify iOS app builds successfully without errors.~~ ✅ **DONE**

- **Verify profile setup flow** — Profile setup should only show on first signup.
  Current code in `RootScreen` checks for `users` row existence, which should
  work correctly. Verify this behavior is working as expected
  (`lib/features/root/root_screen.dart`).

- ~~**Customize pet feeding notifications per food item**~~ ✅ **DONE** — Each
  food type fires its own hunger push independently (`hungry_notified_fish`/
  `_treats`/`_dry_food` on `pets`, `check_hungry_pets()` in
  `supabase/migrations/20260822100000_per_food_hunger_notifications.sql`), with
  food-specific copy (`supabase/functions/send-push/index.ts`) and a tap
  routes straight to `FeedFlowScreen` with that food highlighted
  (`lib/main.dart`, `lib/features/pet/pet_feed_deep_link_screen.dart`,
  `lib/features/pet/feed_flow_screen.dart`).

- ~~**Implement per-food cooloff periods for pet feeding**~~ ✅ **DONE** — Treats: 12h, Fish: 6h, Dry Food: 4h. Independent cooldowns active.

- ~~**Add coin spending mechanism for special pet foods** — Allow users to buy
  special food items with coins. Special foods have cooloff time and depletion
  tracking (limited uses per purchase). Track inventory
  (`lib/features/pet/feed_flow_screen.dart`, `lib/models/food.dart`).~~ ✅ **DONE** — Complete system: DB tables, RPCs, models, repo, shop UI, feed flow integration with unified drag-drop.

- ~~**Add Remind button in friend view** — Show "Remind" button in friend card
  only when net balance is positive (you are owed). Clicking sends notification
  to friend: "X has reminded you about the balance". Hide when you owe friend
  (`lib/features/friends/friends_screen.dart`).~~ ✅ **DONE** — DB RPC `send_friend_remind()`, Edge Function handler, UI button in `FriendDetailScreen` (only shows when balance > 0).

- ~~**Display configured pet name in Pet screen** — Replace "Your Pet" text with
  actual pet name configured by user in pet screen header/title
  (`lib/features/pet/pet_companion_tab.dart`).~~ ✅ **DONE** — `pet_home_screen.dart:127` already displays `pet.name`.

- **Implement Splitwise data import feature** — Allow users to import expenses
  and friends from Splitwise. Use Splitwise API to fetch user's expenses and
  group data.

- **Build marketing landing page** — Create landing page to showcase Meowes app
  features, benefits, and call-to-action for sign up.
