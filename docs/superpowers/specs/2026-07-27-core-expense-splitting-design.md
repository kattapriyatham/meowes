# Meowes — Core Expense Splitting, Groups & Auth (Sub-Project 1)

**Status:** Approved
**Date:** 2026-07-27

## Scope

This is the first of several sub-projects for Meowes (see the full app brief for
overall product context: personal pet companion tied to expense-splitting
behavior, monetization, UPI settle-up, cosmetics). This sub-project covers only
the foundation: auth, friends, groups, expenses, splitting, debt simplification,
and settle-up. The pet/coin/mood system, UPI integration, paywall, OCR, and
charts are separate later sub-projects and are explicitly out of scope here.

## Platform & Stack

- **Client:** Flutter (Dart), targeting iOS + Android from one codebase.
  Chosen over React Native for Skia-based rendering, which gives pixel-identical
  custom UI/animation on both platforms — important because the app's actual
  differentiator (per the brief) is a distinctively illustrated, animated cat
  character, not the splitting mechanic itself.
- **Backend:** Supabase (Postgres + Realtime + Auth + Storage).
  Chosen over Firebase/custom backend because the domain is inherently
  relational (ledger-style balances, debt graphs), and Postgres RPC functions
  let all money-math logic live in one server-side place rather than being
  reimplemented per-client.
- **Auth:** Google / Apple social sign-in. Phone number is collected separately,
  post-signup, purely as a friend-discovery lookup key — it is not the auth
  mechanism.

## Data Model

- `users` — id, name, avatar_url, phone_number (optional, for friend search),
  auth provider fields.
- `groups` — id, name, created_by, invite_code (unique, shareable link token,
  regeneratable by the creator if it leaks).
- `group_members` — group_id, user_id, joined_at.
- `friendships` — user_id_a, user_id_b, status (`pending` / `accepted`),
  requested_by. Created either implicitly (auto-friending when two users share
  an expense via a group invite link) or explicitly (phone-number search +
  friend request, see "Adding Friends" below).
- `expenses` — id, group_id (**nullable** — null means a direct friend expense
  with no group), paid_by, description, amount, currency, expense_date,
  created_at, created_by, edited_at, edited_by, deleted_at (soft delete).
- `expense_splits` — expense_id, user_id, share_amount. Splits are stored as
  resolved amounts (not formulas), so history stays correct regardless of
  original split type (equal / percentage / exact).
- `settlements` — id, group_id (nullable), from_user, to_user, amount,
  status (`pending_confirmation` / `confirmed`), created_at, confirmed_at.

### Balance Computation (server-side RPCs, computed on read — never cached)

1. `get_friend_balance(user_a, user_b)` — nets every expense_split shared
   between two users, across all group and direct expenses, into a single
   signed number (e.g. "Alex owes you ₹450 overall").
2. `get_group_debts(group_id)` — computes raw pairwise balances within a
   group, then runs a greedy min-transaction debt-simplification pass
   (repeatedly match the largest creditor against the largest debtor) to
   produce the minimal set of suggested "smart settle" transactions
   (A owes B, B owes C → simplified to A owes C).

Both are scoped queries (bounded to one friend pair or one group's rows), kept
correct by never being cached — edits/deletes to expenses are reflected
immediately on the next read with no invalidation logic needed. Required
indexes: `expense_splits(group_id)`, `expense_splits(user_id)`,
`expenses(group_id)`.

**Scaling note:** this approach comfortably handles low-thousands-of-registered
users on Supabase's free/entry tier, and tens of thousands with a modest
dedicated compute add-on, without changes. If simultaneously-active users ever
exceed roughly 10k+ hammering balance screens at once, the escape hatch is
materializing a cached `balances` table updated on write — a config-level
change, not a data model change. Not built now; YAGNI until metrics demand it.

## Splitting Logic

Three split types at expense creation, all resolved to concrete
`expense_splits.share_amount` rows at write time:
- **Equal** — amount ÷ participant count, remainder cents distributed to the
  first N participants to avoid rounding leaks.
- **Percentage** — user-specified %, validated (client-side for UX, re-validated
  server-side) to sum to 100%.
- **Exact amounts** — user-specified per participant, validated to sum to the
  total.

## Real-Time Sync

Supabase Realtime subscriptions on `expenses`, `expense_splits`, and
`settlements`, scoped per group and per friend-pair. Any add/edit/delete or
settlement confirmation pushes to other affected members' devices, which
re-run the relevant balance RPC — balances update live without manual refresh.

## Adding Friends

- **Existing registered user:** search by phone number → send a friend request
  (`pending`) → recipient accepts (`accepted`). Deliberately not an instant add,
  consistent with the app's mutual-confirmation pattern (same principle as
  two-sided settle-up — nobody enters your financial graph without their say-so).
- **Not yet registered:** falls back to generating a shareable invite link
  (SMS/WhatsApp) — opening it either joins an existing pending request or
  starts signup, and adds the friendship on completion.
- **Group invite links:** a separate flow — anyone with a group's invite link
  who signs in is added to `group_members`, and implicitly becomes a
  `friendships` (accepted) record with existing group members if not already
  friends.

## Groups

- Created with a name; generates a shareable invite link.
- Members can be added via the group invite link or by adding existing friends
  directly.
- Group debt view shows raw pairwise balances plus "smart settle" suggested
  transactions from `get_group_debts`.

## Expenses

- Can be created **with or without** a group (direct friend expense has
  `group_id = null`).
- Any participant in an expense — not just its creator — can edit or delete it,
  matching Splitwise's model where disputes need to be fixable by anyone
  involved.
- Deletes are soft (`deleted_at`), so a counterparty sees a struck-through
  removed entry rather than an expense silently vanishing; soft-deleted
  expenses are excluded from balance RPCs.
- Edits set `edited_at`/`edited_by` for a simple "edited" indicator on the
  detail screen. Full revision history is a deferred nice-to-have, not a v1
  requirement.

## Settle-Up Flow

Two-sided confirmation, not one-sided:
1. Payer marks a balance (or a "smart settle" suggested transaction) as paid →
   creates a `settlements` row with `pending_confirmation`.
2. Counterparty is notified and must confirm receipt → status flips to
   `confirmed`.
3. Only `confirmed` settlements net against expense-derived balances in the
   RPC calculations — a `pending_confirmation` settlement does not change what
   either party sees as owed.
4. If the counterparty never confirms, the settlement stays pending
   indefinitely and is visibly flagged on both sides — no auto-expiry or
   auto-confirm in v1, to keep the ledger honest.

## Screens

1. **Home** — friends list (net balance per friend, combined across groups +
   direct expenses) and groups list (your balance per group).
2. **Friend detail** — shared expense history (group + direct), running total,
   settle-up action.
3. **Group detail** — member balances, expense list, smart-settle suggestions,
   settle-up action.
4. **Add expense** — participant picker (friends and/or a group), amount,
   description, split type, optional group attachment.
5. **Expense detail** — full expense view with edit/delete actions.
6. **Add friend** — phone number search + request, or invite link fallback.
7. **Create group** — name + invite link generation, add existing friends.
8. **Settle-up flow** — initiate (mark paid) → counterparty confirms/disputes.
9. **Onboarding** — Google/Apple sign-in → profile setup (name, avatar, optional
   phone number) → home screen.

## Error Handling

- Split validation (percentage/exact sums) is checked client-side for UX and
  re-validated server-side before write — client math is never trusted alone
  for money.
- Offline writes (add/edit/delete expense, settle actions) are queued locally
  and replayed on reconnect; Realtime reconciles any state changed elsewhere in
  the meantime. No CRDT-style conflict resolution in v1 — last-write-wins on
  edits is an acceptable trade at this scale.
- Settlement disputes: a declined/ignored confirmation simply stays
  `pending_confirmation`, visibly flagged — no silent auto-resolution.
- Invite link abuse: group invite codes are regeneratable by the group creator.

## Testing

- SQL RPC functions (balance calc, debt simplification, split validation) get
  unit tests against a test Postgres instance — highest-value place to test,
  since this is the money-correctness-critical logic.
- Flutter app: widget/integration tests for the add-expense flow (split math,
  participant selection) and the settle-up flow (pending → confirmed
  transitions).
- No E2E device testing infrastructure for v1; manual testing during the beta
  phase (per the brief's beta plan) covers that gap.

## Explicitly Out of Scope (Later Sub-Projects)

- Pet/mood/coin companion system.
- UPI deep-link settle-up (this sub-project uses manual "mark as settled" only).
- Subscription/paywall (Pro tier, RevenueCat), group pass, lifetime plan.
- Receipt OCR, currency conversion, spending charts/analytics.
- Cosmetic store.
