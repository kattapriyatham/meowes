# Known Issues & Follow-Ups

Tracked gaps surfaced after the core-expense-splitting implementation
(`docs/superpowers/plans/2026-07-27-core-expense-splitting.md`) was built and
reviewed. None of these block the individual tasks that were completed — they're
recorded here so they're visible in the repo rather than only in session state.

## Tracked as separate follow-up tasks

- **`group_members_insert_self` RLS doesn't enforce invite-code possession** —
  the policy only checks `user_id = auth.uid()`, so a client can bypass
  `join_group_by_code` entirely and join any group whose ID they know by
  inserting into `group_members` directly via the REST API. Needs a tighter
  policy (e.g., restrict direct insert to the group creator's own row, route
  all other joins exclusively through the RPC).
- **`ExpenseDetailScreen`'s Edit button creates a duplicate expense instead of
  editing** — it navigates to `AddExpenseScreen`, which only ever calls
  `ExpenseRepository.createExpense`, never `editExpense`. `editExpense` and the
  re-split logic it implies were never actually wired up to any screen.

## Resolved

- ~~Friend Detail showed an empty expense history despite a non-zero
  balance~~ — `get_friend_balance` sums pairwise splits across all expenses
  (no group filter), but `get_shared_expenses` restricted itself to
  `group_id is null`, so group-derived debts moved the balance without ever
  appearing as a line item. Migration `20260728130000_get_shared_expenses_include_groups.sql`
  rewrites `get_shared_expenses` so its row predicate mirrors
  `get_friend_balance`'s two expense terms exactly (payer + counterparty's
  split), dropping the group filter. Friend Detail's AppBar now shows the
  friend's name instead of a hard-coded "Friend". Covered by a new
  authenticated-role case in `run_balance_rpc_tests.sh`.

- ~~No root routing~~ — `main.dart` now routes through `RootScreen`
  (`lib/features/root/root_screen.dart`): signed out → `SignInScreen`, signed
  in with no `users` row yet → `ProfileSetupScreen`, otherwise → `HomeScreen`.
  Verified end-to-end on an Android emulator. `HomeScreen`'s friend/group
  tiles still aren't tappable into their detail screens — that part of the
  original gap remains, see below.
- ~~No way to test without native Google/Apple OAuth config~~ — `SignInScreen`
  has a `kDebugMode`-gated "Sign in as Test User 1/2" path
  (`AuthRepository.signInWithTestAccount`) using two seeded Supabase
  email/password accounts (`testuser1@meowes.dev` / `testuser2@meowes.dev`,
  password `MeowesDevTest123!`), so the app can be exercised without waiting
  on real OAuth setup. The underlying native-config gap (see below) is
  unchanged for the real Google/Apple buttons.

## Not yet tracked as separate tasks

- **`HomeScreen`'s friend/group tiles aren't tappable** — `FriendDetailScreen`
  and `GroupDetailScreen` exist (Task 13) but nothing on `HomeScreen`
  navigates to them yet.
- **Google/Apple sign-in has no native configuration** — the Dart-side calls
  to `google_sign_in`/`sign_in_with_apple` are wired up, but there's no
  `GoogleService-Info.plist`/`google-services.json`, no URL schemes in
  `Info.plist`/`AndroidManifest.xml`, and no OAuth client IDs registered in
  Google Cloud Console or Supabase's Auth provider settings. Tapping either
  real sign-in button will throw. The dev test-account bypass above sidesteps
  this for testing but doesn't fix it.
- **`public_profiles` view is unused** — created to expose non-sensitive
  profile fields (name, avatar) for cross-user display after `users` was
  locked to own-row-only SELECT, but no screen reads it yet; `HomeScreen`
  displays raw user UUIDs instead of names.
- **Migration `0002_balance_rpcs.sql` was edited in place** during early
  iteration, before a forward-only-migration norm was established for this
  project (every fix since has been a new migration file). Not a functional
  issue — all edits were idempotent `create or replace` — but worth knowing if
  diffing migration history against what was actually applied.
