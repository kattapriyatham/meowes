# Store Readiness — App Store & Play Store submission

Tracking doc for everything Meowes needs before it can pass App Store Review
and Google Play review. Derived from an audit on 2026-09-01 against the App
Store Review Guidelines and Google Play Developer Program Policies.

## Launch plan: Android (Google Play) first

iOS / App Store submission is **deferred**. Apple-only tasks are marked
`DEFERRED (iOS)` and excluded from the Android launch count. The iOS-side code
that's already written (Sign in with Apple, entitlements) stays in the tree,
inert on Android, ready for when iOS is picked up.

## How to use this doc

- Update the **Status** cell as work progresses: `TODO` → `IN PROGRESS` → `IN REVIEW` → `DONE` (or `BLOCKED` / `DEFERRED` / `N/A`).
- Keep the **Progress** table below in sync.
- Each task lists its acceptance criteria — don't mark `DONE` until they're all met.
- P0 = hard blocker (guaranteed rejection). P1 = likely rejection or listing cannot be completed. P2 = polish / risk reduction.

## Progress (Android launch)

| Priority | In scope | Deployed | Device-verify pending | Remaining | Deferred (iOS) |
|----------|----------|----------|-----------------------|-----------|----------------|
| P0       | 6        | P0-6 site + P0-1/4/5 migrations | P0-1, P0-3, P0-4, P0-5 | P0-7 keystore | P0-2 |
| P1       | 6        | —        | —                     | 6         | — |
| P2       | 8        | —        | —                     | 8         | — |

Both new Supabase migrations are **live on the production project**. The legal +
marketing site is **live** at `https://meowes-b2e69.web.app/`. What's left for
P0: generate the upload keystore (P0-7), device-verify the new flows, and the
Play Console listing/forms.

### Changelog
- 2026-09-01 — **DEPLOYED:** `supabase db push` applied both migrations
  (`20260901120000_account_deletion`, `20260901130000_reports_and_blocking`) to
  the live project — verified: 2 new tables, 3 new functions, `users_id_fkey`
  dropped, block trigger live, `users.deleted_at` added. `firebase deploy --only
  hosting` published `site/` — landing + all legal pages live and 200 at
  `https://meowes-b2e69.web.app/`. Release `.aab` + `.apk` built (still
  debug-signed — P0-7).
- 2026-09-01 — **Android-first** decided. P0-2 (Sign in with Apple) → DEFERRED (iOS).
- 2026-09-01 — P0-4 + P0-5 landed: `20260901130000_reports_and_blocking.sql`
  (`content_reports`, `blocked_users`, `block_user()` RPC, friendship-block
  trigger, `send_friend_remind` block guard — validated in a rolled-back tx);
  `reportContent` / `blockUser` / `removeFriend` repo methods; `showReportSheet`
  bottom sheet; Report/Block/Remove menu on friend detail, Report action on
  group + expense detail; repo + widget tests.
- 2026-09-01 — P0-3: `--dart-define=MEOWES_REVIEW=1` exposes the seeded
  test-account sign-in for Play review (alongside kDebugMode).
- 2026-09-01 — P0-7: `android/app/build.gradle.kts` now reads
  `android/key.properties` for release signing (debug fallback when absent);
  `android/key.properties.example` added; `android/.gitignore` already covers it.
- 2026-09-01 — P0-6: marketing + legal site restructured under `site/`
  (`site/index.html` = the old `landing.html`, `site/legal/*.html`,
  `site/landing_assets/`). `firebase.json` given a `hosting` block
  (`public: "site"`), `.firebaserc` pins project `meowes-b2e69`. Footer links
  wired; verified locally that `/`, `/legal/*.html` and assets all serve.
  Deploy with `firebase deploy --only hosting`.
- 2026-09-01 — P0-2 app code landed (Apple button re-added iOS-only, nonce-based
  `signInWithApple`, entitlements file + pbxproj wiring, widget tests).
- 2026-09-01 — P0-1 app code + migration landed (`delete_my_account` RPC —
  anonymise + keep shared history, drops `users_id_fkey`; `DeleteAccountScreen`
  with typed confirmation; Profile entry; widget + repo tests). Migration
  syntax-validated against the live DB in a rolled-back transaction. **Not yet
  pushed** (`supabase db push`) and not device-verified.

### What YOU need to do to ship the Android build

~~1. `supabase db push`~~ — **DONE 2026-09-01**, both migrations live + verified.
~~2b. `firebase deploy --only hosting`~~ — **DONE**, site live at
`https://meowes-b2e69.web.app/` (privacy `/legal/privacy.html`, deletion
`/legal/delete-account.html`, terms `/legal/terms.html`, support `/legal/support.html`).

Still to do:

1. **Keystore (P0-7).** `keytool -genkey -v -keystore meowes-upload.jks -keyalg
   RSA -keysize 2048 -validity 10000 -alias upload`, create `android/key.properties`
   from `android/key.properties.example`, back it up, enrol in Play App Signing.
   Then `flutter build appbundle --release` via the wrapper produces a
   Play-ready `.aab`. (The current `.aab`/`.apk` are debug-signed — not valid for upload.)
2. **Play Console listing + App content:** short/full description (say "split
   expenses / track balances / record settlements" — never "send money"),
   screenshots + feature graphic, content rating questionnaire, **Data safety**
   form (see P1-3), **account deletion URL** =
   `https://meowes-b2e69.web.app/legal/delete-account.html`, **privacy policy URL**
   = `.../legal/privacy.html`, **App access** = reviewer login (seeded Google
   account, or ship the first `.aab` with `--dart-define=MEOWES_REVIEW=1` and
   name the two `testuser@meowes.dev` accounts).
3. **Device-verify** on a real Android device against the now-live DB:
   - Delete account → sign back in with same Google account → fresh profile; a
     friend's balance with you still reconciles and shows "Deleted user".
   - Report an expense/group/user → row lands in `content_reports`.
   - Block a user → can't re-friend via invite link or request; Remind fails.
4. **(Recommended) legal review** of `site/legal/privacy.html` + `terms.html`
   for India; and confirm the 30-day backup-retention claim matches your
   Supabase plan.
5. **(Optional now)** custom domain in Firebase console; in-app Profile → Legal
   links (P1-1).

---

## P0 — Hard blockers

### P0-1 · In-app account deletion
- **Status:** MIGRATION DEPLOYED — device verify + Apple-revoke sub-task remain
- **Why:** Apple Guideline 5.1.1(v) and Google Play's Account Deletion policy both require that any app supporting account creation lets the user *initiate* account deletion from inside the app. Meowes' Profile screen currently offers only "Sign out".
- **Done:**
  - `supabase/migrations/20260901120000_account_deletion.sql` — adds `users.deleted_at`, drops `users_id_fkey` (so deleting the auth row doesn't cascade the anonymised tombstone), and `delete_my_account()` `security definer` RPC: scrubs the profile to "Deleted user" (null phone/avatar), deletes friendships / device_tokens / group_members / food_inventory / pet_memories / pets / unconfirmed settlements, then deletes `auth.identities` + `auth.users`. Keeps expenses + confirmed settlements (anonymised) so other members' balances still reconcile. **Validated** by running the whole migration inside a `begin … rollback` against the live DB — no errors, DB untouched.
  - `AuthRepository.deleteAccount()` — calls the RPC then signs out.
  - `lib/features/profile/delete_account_screen.dart` — explains what's deleted vs kept, requires typing `DELETE`, uses `runAction` (spinner + Retry), routes to sign-in on success.
  - Profile screen has a red "Delete account" entry.
  - Tests: `test/features/profile/delete_account_screen_test.dart` (3).
- **Remaining:**
  - [ ] `supabase db push` the migration to the linked project (your call — it drops a constraint + adds a function on the live DB).
  - [ ] Verify end-to-end on a device: delete account, confirm sign-in with the same Google account creates a fresh profile, confirm a friend's balance with you still reconciles and shows "Deleted user".
  - [ ] Apple token revocation — when the user signed in with Apple, Apple requires calling their `/auth/revoke` endpoint on deletion. Needs the Apple client secret, so it belongs in an edge function called from `delete_my_account`'s client flow. Tracked here, do alongside P0-2.
  - [ ] Public web deletion page = P0-6.
- **Original scope notes below.**
- **Scope:**
  - New screen: Profile → "Delete account" → warning + typed confirmation → calls a server RPC → signs out → routes to sign-in.
  - New Supabase migration: `delete_my_account()` `security definer` RPC that removes / anonymises, for `auth.uid()`:
    - `users` row, `pets` row, pet `memories`, food inventory
    - `friendships` where the user is either side
    - `push_tokens`
    - authored `expenses` (+ `expense_splits`) and `settlements` — decide: hard-delete vs. anonymise so the *other* party's history still reconciles. Recommended: anonymise the leaving user's identity, keep the expense rows, so balances for remaining members stay correct.
    - finally delete the `auth.users` row (via `auth.admin` in an edge function, or schedule it) so the account can't sign back in.
  - Client repo method + `runAction` wiring + confirm dialog.
- **Acceptance:**
  - [ ] From a signed-in device, Profile → Delete account → confirm removes the account and lands on sign-in.
  - [ ] Signing in again with the same Google account creates a fresh profile (no stale data).
  - [ ] A friend who shared expenses with the deleted user still sees correct balances.
  - [ ] Deletion also works from the public web page (see P0-6).
- **Files:** `lib/features/profile/profile_screen.dart`, new `lib/features/profile/delete_account_screen.dart`, new `supabase/migrations/*_account_deletion.sql`, possibly `supabase/functions/delete-account/`.

### P0-2 · Sign in with Apple (iOS)
- **Status:** DEFERRED (iOS) — app code already written; not needed for the Android launch (Guideline 4.8 is Apple-only). Pick up when starting the iOS submission.
- **Why:** Apple Guideline 4.8. The "Continue with Apple" button was removed this cycle, leaving Google as the only third-party login and no first-party email/password. 4.8 requires an equivalent login option that limits data to name + email, supports hiding the email, and doesn't collect interactions for advertising — Sign in with Apple satisfies this.
- **Done (code):**
  - `signInWithApple()` rewritten with the nonce flow Supabase requires (raw nonce → SHA-256 to Apple, raw nonce to Supabase). `lib/repositories/auth_repository.dart`.
  - Apple button re-added, **iOS only** via `!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS`. `lib/features/auth/sign_in_screen.dart`.
  - `handleSignIn` now swallows user-cancel and shows a SnackBar on real failures.
  - `ios/Runner/Runner.entitlements` created (`com.apple.developer.applesignin` = Default) and `CODE_SIGN_ENTITLEMENTS` wired into all 3 Runner build configs in `project.pbxproj`.
  - `crypto` added to `pubspec.yaml`.
  - Tests: `test/features/auth/sign_in_screen_test.dart` (Apple shows on iOS, hidden on Android).
- **Remaining (needs Apple Developer account — cannot be done from code):**
  - [ ] Enable the "Sign in with Apple" capability on App ID `com.meowes.meowesApp` in the Apple Developer portal; regenerate provisioning profiles.
  - [ ] Create a Services ID + private key (.p8) for Apple; configure the **Apple provider** in Supabase Auth (Services ID / Team ID / Key ID / key). Add `com.meowes.meowesApp` to allowed client IDs.
  - [ ] In Xcode: confirm the "Sign in with Apple" capability shows on the Runner target (the entitlement is already wired; Xcode should pick it up).
  - [ ] Verify end-to-end on a real iOS device / TestFlight build — including the "Hide My Email" path.
  - [ ] Add Apple token revocation to the account-deletion flow (P0-1).
- **Files:** `lib/features/auth/sign_in_screen.dart`, `lib/repositories/auth_repository.dart`, `ios/Runner/Runner.entitlements`, `ios/Runner.xcodeproj/project.pbxproj`, `pubspec.yaml`, Supabase Auth config, Apple Developer portal.

### P0-3 · Reviewer access / demo account
- **Status:** CODE DONE — Play Console step pending
- **Why:** The app is login-gated. Play's "App access" section must describe how a reviewer signs in.
- **Done:** `--dart-define=MEOWES_REVIEW=1` now exposes the seeded "Sign in as Test User 1 / 2" buttons in a release build (previously `kDebugMode`-only). `lib/features/auth/sign_in_screen.dart`, `_reviewBuild` const.
- **Remaining (you):** pick one and record it in Play Console → App access:
  - **A (no code):** create a dedicated Google account, seed it with demo data, give the credentials to Play. Play reviewers run real Android and can complete Google OAuth. Use an account without 2FA.
  - **B:** build the first submission's AAB with `--dart-define=MEOWES_REVIEW=1`, tell Play to use "Reviewer sign-in → Test User 1". Test accounts: `testuser1@meowes.dev` / `testuser2@meowes.dev`, password `MeowesDevTest123!` (rotate before launch).
- **Acceptance:**
  - [ ] A reviewer following the App-access notes can sign in on the exact build submitted.

### P0-4 · Report content / user
- **Status:** MIGRATION DEPLOYED — device verify + triage view (P0-4) remain
- **Why:** Play UGC policy (and Apple 1.2). Expense descriptions, group names, pet names and "Remind" pings are user-to-user content, and invite links let anyone become a friend instantly.
- **Done:**
  - `supabase/migrations/20260901130000_reports_and_blocking.sql` — `content_reports` table (reporter can insert + read own; team triages via dashboard/service role), indexed on `(status, created_at)`. Validated in a rolled-back tx.
  - `FriendRepository.reportContent({targetType, targetId, reason, details})`.
  - `showReportSheet()` — reason picker + optional detail + success toast ("we'll review within 24 hours"). `lib/features/moderation/report_sheet.dart`.
  - Wired: friend detail (overflow → Report), group detail (flag icon), expense detail (flag icon).
  - Tests: `reportContent` repo test, `report_sheet_test.dart`.
- **Remaining (you):**
  - [ ] `supabase db push`.
  - [ ] Stand up a triage view (Supabase dashboard filter on `content_reports.status='open'`, or a small internal tool) and a published moderation contact.
  - [ ] Play "App content" → describe the report + moderation workflow.

### P0-5 · Block user + remove friend
- **Status:** MIGRATION DEPLOYED — device verify + triage view (P0-4) remain
- **Why:** Play UGC/social policy (and Apple 1.2) — users must be able to block abusive people.
- **Done (same migration as P0-4):**
  - `blocked_users` table + own-row RLS.
  - `block_user(p_target)` RPC — records the block and deletes any friendship between the pair.
  - `trg_reject_blocked_friendship` — `before insert/update on friendships` trigger raises `blocked` in either direction, covering `sendFriendRequest`, accept, and `join_friendship_by_code`.
  - `send_friend_remind` re-created with a block guard at the top.
  - `FriendRepository.blockUser()` / `removeFriend()`; friend-detail overflow menu → Report / Block / Remove (Block & Remove confirm-dialog, then pop).
  - Tests: `blockUser` + `removeFriend` repo tests.
- **Remaining (you):**
  - [ ] `supabase db push`.
  - [ ] Verify on device: block prevents re-friend via invite link + request; Remind between a blocked pair fails.

### P0-6 · Hosted legal + deletion pages
- **Status:** LIVE — https://meowes-b2e69.web.app/legal/* ; paste URLs into Play Console
- 2026-09-01: placeholders filled — operator "Priyatham Katta, individual
  developer, India"; contact `meowesapp@gmail.com` (both privacy + support);
  governing law India; 30-day retention; draft banners removed. Legal review
  still advisable but the pages are publishable.
- **Why:** Play requires a hosted **Privacy Policy** URL and a public **account-deletion request** URL.
- **Done:**
  - `site/legal/privacy.html`, `terms.html`, `delete-account.html`, `support.html`
    — self-contained pages with Meowes' actual data disclosures (Google identity,
    phone, expense data, friend graph, FCM token; no ads/tracking SDKs;
    anonymise-and-keep retention).
  - Marketing + legal now live together under `site/` (`site/index.html` = the
    old `landing.html`; `site/landing_assets/`). Footer wired to `/legal/*`.
  - `firebase.json` `hosting` block (`public: "site"`, `cleanUrls: false`);
    `.firebaserc` → project `meowes-b2e69`. Verified locally: `/`, all four
    `/legal/*.html`, and assets serve 200.
- **Remaining (you):**
  - [ ] Replace every `[bracketed]` blank in `site/legal/*.html` — legal entity, address, contact email, jurisdiction, retention days. Ideally a lawyer skim.
  - [ ] `firebase deploy --only hosting` → pages at `https://meowes-b2e69.web.app/legal/...` (needs `firebase login` first).
  - [ ] Paste Privacy Policy URL + account-deletion URL into the Play listing / App content.
  - [ ] (P1-1) add the in-app **Profile → Legal & privacy** links pointing at the deployed base URL.

### P0-7 · Release signing (Android)
- **Status:** CODE DONE — keystore generation pending
- **Why:** the release build was debug-signed; Play rejects that.
- **Done:** `android/app/build.gradle.kts` reads `android/key.properties` (git-ignored via `android/.gitignore`) for a real `release` signingConfig, with a debug fallback when the file is absent so `flutter run --release` still works locally. `android/key.properties.example` documents the format + `keytool` command.
- **Remaining (you):**
  - [ ] `keytool -genkey … -keystore meowes-upload.jks -alias upload`, create `android/key.properties`, back up the keystore + passwords.
  - [ ] Enrol in Play App Signing.
  - [ ] `flutter build appbundle --release` via the wrapper (add an appbundle path to `scripts/build_android.sh` or run with the dart-defines) → upload the `.aab`.
- **Files:** `android/app/build.gradle.kts`, `android/key.properties` (you create), `android/key.properties.example`.

---

## P1 — Likely rejection / cannot complete listing

### P1-1 · In-app Privacy Policy + Terms links
- **Status:** TODO
- **Why:** Apple 5.1.1(i) — privacy policy must be accessible *in* the app, not only the listing.
- **Scope:** Profile → "Legal & privacy" section: Privacy Policy, Terms, and "Request my data" (mailto is fine to start). Open in an in-app browser / external browser.
- **Acceptance:** [ ] All three reachable from Profile on both platforms.
- **Files:** `lib/features/profile/profile_screen.dart`.

### P1-2 · Apple Privacy Nutrition Label
- **Status:** TODO
- **Why:** Required in App Store Connect; must match real data collection or it's a rejection / post-launch removal.
- **Scope:** Declare: Contact info (email, phone), Financial info (expense amounts + descriptions — "Other financial info"), User content, Identifiers (push token), Usage data only if analytics added. Map each to purpose + linkage.
- **Acceptance:** [ ] Label submitted and matches an actual data-flow inventory.

### P1-3 · Play Data Safety form
- **Status:** TODO
- **Why:** Required in Play Console; mismatch = rejection.
- **Scope:** Same data inventory as P1-2. Declare encryption in transit, the in-app + URL deletion paths (P0-1/P0-6), and data types collected/shared.
- **Acceptance:** [ ] Form submitted and consistent with the Apple label.

### P1-4 · Android 13+ notification permission
- **Status:** TODO
- **Why:** `POST_NOTIFICATIONS` is not declared in `AndroidManifest.xml`; on Android 13+ the runtime prompt won't fire without it, so push silently never works — and a broken advertised feature is a rejection risk.
- **Scope:** Add `<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>`; verify `FirebaseMessaging.requestPermission()` triggers the OS dialog on a 13+ device/emulator; add a short pre-permission explainer.
- **Acceptance:**
  - [ ] Fresh install on Android 14 shows the notification prompt at the right moment.
  - [ ] Denying it leaves the rest of the app fully usable.
- **Files:** `android/app/src/main/AndroidManifest.xml`, `lib/core/push_notifications.dart`.

### P1-5 · iOS Info.plist compliance keys
- **Status:** TODO
- **Why:** `ITSAppUsesNonExemptEncryption` absent → every TestFlight/submission upload prompts for export compliance. Also confirm no permission is used without a usage string.
- **Scope:** Add `ITSAppUsesNonExemptEncryption = false` (HTTPS-only, no custom crypto). Audit for any camera/photos/contacts/location usage (none expected — phone number is typed, not read from Contacts) and add strings only if needed. Set `CFBundleDisplayName` correctly.
- **Acceptance:** [ ] Upload no longer prompts for export compliance. [ ] No missing-usage-string crash on any screen.
- **Files:** `ios/Runner/Info.plist`.

### P1-6 · Store listing copy review
- **Status:** TODO
- **Why:** Describing Meowes as a payments/"send money" app invites financial-services scrutiny and IAP questions. It only *records* settlements made outside the app (like Splitwise).
- **Scope:** Description, subtitle, keywords, screenshots must say "split expenses", "track balances", "record settlements" — never "send/transfer money" or "payments". Age-rating questionnaire answered honestly for UGC + user communication. "Does the app contain digital purchases?" → No (coins are earn-only, no `in_app_purchase`).
- **Acceptance:** [ ] Copy reviewed on both stores. [ ] Age rating completed.

---

## P2 — Polish / risk reduction

### P2-1 · Offline / backend-down resilience
- **Status:** TODO
- **Why:** Reviewers test airplane mode. Sign-in and first load must degrade with a message, not a spinner forever or a crash.
- **Acceptance:** [ ] Airplane-mode launch shows a friendly retryable state on sign-in and home.

### P2-2 · GlassButton async support (sign-out loader)
- **Status:** TODO
- **Why:** Sign-out has no loader/disable (unlike the `PillButton`/`runAction` rollout). Low-stakes but inconsistent.
- **Acceptance:** [ ] Sign-out shows a spinner and can't be double-tapped.
- **Files:** `lib/core/widgets/glass/glass_button.dart`, `lib/features/profile/profile_screen.dart`.

### P2-3 · shareInviteLink loader
- **Status:** TODO
- **Why:** `shareInviteLink` does an async `getMyInviteCode()` network call with no feedback; tap looks dead for a beat.
- **Acceptance:** [ ] Tapping "Share invite link" shows progress until the share sheet opens; failure shows a retry.
- **Files:** `lib/features/friends/add_friend_screen.dart`.

### P2-4 · Home daily check-in error handling
- **Status:** TODO
- **Why:** `_loadAndCheckIn` only catches `AlreadyCheckedInException`; a network error there is uncaught.
- **Acceptance:** [ ] A failed check-in is silent-safe (no uncaught exception, no user-facing noise).
- **Files:** `lib/features/home/home_screen.dart`.

### P2-5 · iOS Universal Links (optional)
- **Status:** TODO
- **Why:** `meowes://invite/<code>` is a custom scheme — works, but https Universal Links are higher-trust and survive being pasted into Messages/Mail.
- **Scope:** Host `apple-app-site-association`, add associated-domains entitlement, add an `https://` invite host alongside the custom scheme.
- **Acceptance:** [ ] An `https://` invite link opens the app directly on iOS.

### P2-6 · Android App Links verification (optional)
- **Status:** TODO
- **Why:** Same rationale as P2-5 for Android; `autoVerify` + `assetlinks.json`.
- **Acceptance:** [ ] Verified App Link opens the app without the disambiguation dialog.

### P2-7 · Data-flow inventory doc
- **Status:** TODO
- **Why:** Single source of truth that P0-6, P1-2, P1-3 must all agree with.
- **Scope:** Table of every data type collected, where, why, retention, third parties (Supabase, Firebase/FCM, Google Sign-In, Apple).
- **Acceptance:** [ ] Doc exists and the privacy policy + both store forms are generated from it.

### P2-8 · Screenshots + assets
- **Status:** TODO
- **Why:** Both stores need device-frame screenshots at required sizes; Apple needs 6.7"/6.5"/5.5" (or current equivalents) and iPad if the app ships universal; Play needs phone + feature graphic.
- **Acceptance:** [ ] All required sizes generated and uploaded.

---

## Out of scope (confirmed OK, no action)

- **In-app purchases** — no `in_app_purchase` dependency; pet coins are earn-only (daily check-in, feeding rewards) and spent only on virtual food. No IAP obligations. Keep it that way.
- **In-app payments** — "Settle up / Mark as Paid" only records that money moved *outside* the app. No money movement in-app, so no financial-services / PSD2 obligations.
- **Contacts permission** — phone number is typed by the user, never read from the address book.
