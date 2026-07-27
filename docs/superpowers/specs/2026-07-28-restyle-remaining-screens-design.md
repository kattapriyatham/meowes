# Restyle remaining screens — design

Follow-up to the Home screen restyle (`lib/core/app_theme.dart`,
`lib/features/home/home_screen.dart`). Applies the same warm cream/coral
design system, established from the mockup at `docs/designs/image.png`, to
every other existing screen in the app. Styling only — no new screens, no
repository/RPC changes, no new data flows.

## Scope

In scope (9 existing screens):

- `lib/features/auth/sign_in_screen.dart`
- `lib/features/auth/profile_setup_screen.dart`
- `lib/features/friends/add_friend_screen.dart`
- `lib/features/friends/friend_detail_screen.dart`
- `lib/features/groups/create_group_screen.dart`
- `lib/features/groups/group_detail_screen.dart`
- `lib/features/expenses/add_expense_screen.dart`
- `lib/features/expenses/expense_detail_screen.dart`
- `lib/features/settlements/settle_up_screen.dart`

Out of scope: Activity feed and Friend Requests list — these don't exist as
screens yet and building them is net-new feature work, not a restyle. Also
out of scope: any change to repository methods, RPC calls, or the
`AuthRepository`/`FriendRepository`/`GroupRepository`/`ExpenseRepository`/
`SettlementRepository` data-fetch logic. Each screen keeps its existing
`FutureBuilder`/`StreamBuilder` data plumbing; only the widget tree
presentation changes.

One small piece of non-styling work is bundled in because it blocks reaching
two of these screens at all: Home's `_FriendTile` and `_GroupTile`
(`lib/features/home/home_screen.dart`) become tappable, navigating to
`FriendDetailScreen`/`GroupDetailScreen`. This closes the "friend/group
tiles aren't tappable" gap tracked in `docs/superpowers/known-issues.md`.

## Shared widgets (`lib/core/widgets/`)

Home screen's `_FriendTile`/`_GroupTile` already duplicate the same four
pieces of presentation. Promoting them to shared widgets before they repeat
across 9 more screens:

- **`AppCard`** — white rounded container (`BorderRadius.circular(16)`,
  padding), the base "row card" used everywhere a friend/group/expense/
  settlement is listed.
- **`BalanceAmount`** — takes a numeric balance, renders the signed `₹`
  amount in the correct color (`AppColors.owedText`/`owingText`) or
  "Settled" in `AppColors.settledText` when ~0. Used for friend balances,
  group net balances, and settle-up amounts.
- **`AppAvatar`** — circular avatar: colored background from
  `AppColors.avatarFor(seed)`, initial letter or an icon (e.g. group icon)
  in the center. Replaces the ad-hoc `CircleAvatar`/`Container` pairs in
  `_FriendTile`/`_GroupTile`.
- **`EmptyStateBox`** — icon + centered muted message in a white rounded
  box. Same shape as Home's "No friends yet"/"No groups yet" states, reused
  for e.g. an empty expense history or empty recent-friends list.
- **`SectionHeader`** — bold section title text, exactly Home's
  `_SectionHeader` promoted out.
- **`AvatarStack`** — a row of overlapping `AppAvatar`s (see the interaction
  patterns section below) for showing a group's members at a glance.

`home_screen.dart` is updated to use these shared widgets in place of its
current private `_FriendTile`/`_GroupTile`/`_SectionHeader`/`_EmptyState`,
so there's exactly one definition of each pattern.

## Additional interaction patterns (from reference inspiration)

The user shared four bill-splitting app mockups mid-review. Four patterns
from them are folded in below; the rest (notification feeds, a phone-dialer
UI) don't apply here and Home's existing balance card keeps its own
cat/cream/coral language rather than adopting another app's palette.

- **Avatar stack**: a row of overlapping circular `AppAvatar`s (each offset
  ~20px left over the previous, later avatars painted on top), used on
  Group Detail to show that group's members at a glance.
- **Exact-split sliders**: Add Expense's Exact split mode gets one
  `Slider` per participant (0 to the total amount), each row showing the
  participant's name, current ₹ amount, and a live running total vs. target
  at the top ("Remaining ₹0" once balanced, matching mockup #8's own
  "Remaining" field) — same idea as mockup #8, executed with drag instead
  of typed numbers.
- **Recent-contacts avatar row**: Add Friend gets a horizontal scrolling
  row of `AppAvatar`s above the search results, sourced from
  `FriendRepository.watchFriendships()`'s already-accepted friends (no new
  query — reuses the same data Home's Friends section fetches), so
  frequently-contacted people are one tap away without typing a phone
  number.
- **Colorful icon tiles for split type**: Add Expense's Equal/Percentage/
  Exact picker becomes three tappable rounded tiles (each a distinct
  `AppColors.avatarPalette` color, with an icon — `Icons.balance` for
  Equal, `Icons.percent` for Percentage, `Icons.tune` for Exact) instead of
  a plain segmented control, with the selected tile outlined.

**Scope note**: implementing the Exact-split sliders surfaces that
`add_expense_screen.dart` currently never collects `percentages`/
`exactAmounts` at all — `ExpenseRepository.createExpense` (line 38) is
always called with both `null`, so picking Percentage or Exact today would
throw inside `SplitCalculator` the moment a real amount split is attempted
(`split_calculator.dart:37` and `:64`). Since building a slider that doesn't
actually feed the save action would be worse than not building it, this
pass also wires the collected per-participant percentages/exact amounts
into the existing `createExpense` call. This is the one place UI work spills
into behavior, and it's strictly filling in what the current screen's own
`SplitType` picker already implies it should do.

## Per-screen changes

All screens keep `Scaffold`'s default `scaffoldBackgroundColor` (cream, from
`AppTheme.light`) and `AppBarTheme` (transparent cream, dark text) — no
per-screen override needed, just removing any explicit white/default
`Scaffold`/`AppBar` colors that fight the theme.

- **Sign In** (mockup #1): cat mascot + "Meowes / Split expenses. Stronger
  friendships." hero text, centered. Google/Apple sign-in as full-width
  pill buttons (theme's `ElevatedButtonTheme`, Apple button using the
  theme's dark variant or an outlined style since it's normally
  black-on-white). The `kDebugMode`-gated test-account buttons stay
  functional but rendered as a small de-emphasized text link/section below
  a divider, not competing visually with the real sign-in buttons.
- **Profile Setup** (mockup #2): circular avatar placeholder with a camera
  badge (static — no image picker wiring, that's out of scope), name and
  phone fields using the theme's `InputDecorationTheme`, coral "Continue"
  button.
- **Friend Detail** (mockup #4): full-width colored balance card at top
  (`BalanceAmount` + "You are owed"/"You owe" label, same pattern as Home's
  summary card), "Add Expense"/"Settle Up" pill buttons side by side
  (Settle Up only shown when the signed-in user owes, matching existing
  logic in `friend_detail_screen.dart:28`), expense history as a list of
  `AppCard`s (currently this screen has no expense history — this pass
  keeps it to what the screen already fetches: the balance and the settle
  action; no new query added).
- **Group Detail** (mockup #4 group variant): an avatar stack of the
  group's members, "Smart Settle" suggestions re-styled as `AppCard` rows
  showing names instead of raw UUIDs (currently `'${d['from_user']} owes
  ${d['to_user']}'` renders literal UUIDs — this pass resolves them via
  `FriendRepository.getPublicProfiles`, the same already-existing method
  Home uses, plus a `group_members` select for the member list; no new
  repository/RPC method is added). Settle-tap logic
  (`group_detail_screen.dart:34`, only the actual debtor's row is tappable)
  is unchanged.
- **Add Friend** (mockup #10): a horizontal recent-contacts avatar row
  (sourced from already-accepted friendships) above a styled phone search
  field, result as an `AppCard` row with a coral "Send Request" button. The
  mockup's "Share Invite Link" button is dropped from this pass: there's no
  backend mechanism for a friend-invite link today (only groups have
  `invite_code`; the existing "Invite-link generation reuses the group
  invite_code mechanism... wired as a share-sheet action" comment in
  `add_friend_screen.dart` is itself flagging this as unbuilt future work).
  Adding a button with nothing real to call would be worse than not adding
  it, so the "not registered" fallback text stays as plain text.
- **Create Group** (mockup #12): styled group-name field, coral "Create
  Group" button, then — once created — the screen switches to an
  invite-code state showing the new group's `inviteCode` in a muted
  `AppCard` (copy-to-clipboard via `Clipboard.setData`) with a "Done" button
  to pop back. The mockup's member-checklist-at-creation is dropped: nothing
  in `GroupRepository` supports adding members at creation time (`createGroup`
  only ever adds the creator; other members join later via
  `joinByInviteCode`) — building a checklist with no repository call behind
  it would be fake UI, so member selection stays out of scope here.
- **Add Expense** (mockup #6/7/8): description/amount fields, paid-by radio
  row, participants checklist, split-type picker as three colorful icon
  tiles (Equal/Percentage/Exact). Equal shows nothing further (existing
  behavior). Percentage shows one styled numeric field per participant plus
  a running "Total: X% (needs to be 100%)" line. Exact shows one slider per
  participant (0 to the total) plus a running "Remaining ₹X" line; both
  percentages and exact amounts are now collected into state and passed to
  `ExpenseRepository.createExpense`'s `percentages`/`exactAmounts`
  parameters (previously always `null` — see the scope note above). Coral
  "Save Expense" button, disabled while a Percentage/Exact split doesn't
  yet balance to 100%/the total.
- **Expense Detail** (mockup #9): amount + description header, participant
  shares as a list, "Edit"/"Delete" as outlined pill buttons. Must keep
  rendering the "Edited" indicator that `expense_detail_screen_test.dart`
  asserts on.
- **Settle Up** (mockup #13): large amount display, "Mark as Paid" coral
  button, pending-confirmation state text style using `AppColors.settledText`
  once marked.

## Data flow / error handling

No change. Every screen already has its data-fetch pattern (repository
method + `Future`/`StreamBuilder`, or direct RPC call via
`supabaseClientProvider`); this pass only changes what wraps that data.
Where a screen's error/loading state currently has no explicit handling
(most don't — they fall back to empty/zero, matching the existing codebase
convention), that convention is preserved rather than introduced newly here.

## Testing

- `flutter test` must stay green throughout, in particular
  `test/features/home/home_screen_test.dart` (still asserts on literal
  `'Friends'`/`'Groups'` text) and
  `test/features/expenses/expense_detail_screen_test.dart` (asserts on Edit/
  Delete buttons and the edited indicator).
- No new automated tests are added as part of this pass — it's a visual
  restyle of already-implemented screens with unchanged behavior.
- After Home's tiles become tappable, Friend Detail and Group Detail are
  spot-checked live on the Android emulator against the seeded test data
  (Sam/John/Priya, Goa Trip/Flatmates) already in the linked Supabase
  project, since those two screens call the same balance/debt RPCs that
  turned up real bugs during Home's verification.
