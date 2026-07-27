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

## Not yet tracked as separate tasks

- **No root routing** — `main.dart` still shows the Task 1 placeholder
  (`Scaffold(body: Center(child: Text('Meowes')))`). Nothing wires
  `SignInScreen → ProfileSetupScreen → HomeScreen` together, and `HomeScreen`'s
  friend/group tiles aren't tappable into their detail screens. The app has no
  real navigable flow yet.
- **Google/Apple sign-in has no native configuration** — the Dart-side calls
  to `google_sign_in`/`sign_in_with_apple` are wired up, but there's no
  `GoogleService-Info.plist`/`google-services.json`, no URL schemes in
  `Info.plist`/`AndroidManifest.xml`, and no OAuth client IDs registered in
  Google Cloud Console or Supabase's Auth provider settings. Tapping either
  sign-in button will throw.
- **`public_profiles` view is unused** — created to expose non-sensitive
  profile fields (name, avatar) for cross-user display after `users` was
  locked to own-row-only SELECT, but no screen reads it yet; `HomeScreen`
  displays raw user UUIDs instead of names.
- **Migration `0002_balance_rpcs.sql` was edited in place** during early
  iteration, before a forward-only-migration norm was established for this
  project (every fix since has been a new migration file). Not a functional
  issue — all edits were idempotent `create or replace` — but worth knowing if
  diffing migration history against what was actually applied.
