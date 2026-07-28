# Friend Detail activity list — design

## Problem

Friend Detail's "Expense history" is a flat list of individual expenses
showing each expense's **raw total** (e.g. "Groceries ₹1200.00"). This
doesn't match how the header balance is computed and it lists every group
expense separately instead of rolling them up under the group.

Target behaviour (per the Splitwise reference the user provided): a
single **activity list** where each row is either a direct expense or a
shared group (shown by group name), and the amount on each row is the
**net the current user owes / is owed for that row**, colour-coded. The
rows reconcile to the "You owe ₹X" header.

## Decisions (confirmed with user)

1. **Row amount** — net for the current user, colour-coded: `net > 0`
   → green "you lent ₹X", `net < 0` → red "you owe ₹X". Rows sum to the
   header balance.
2. **Settled rows** — rows with `net == 0` are hidden by default; a
   "Show settled" toggle reveals them.
3. **Direct expenses** — listed individually (one row each); group
   expenses are collapsed into one row per group, labelled by group name.

## Sign convention

Matches the existing `get_friend_balance(user_a, user_b)` where
`user_a = me`, `user_b = friend`:

- `net > 0` → the friend owes me (I lent).
- `net < 0` → I owe the friend.

Per-expense net formula (mirrors the two expense terms of
`get_friend_balance`):

```
net(expense) = (case when paid_by = me     then <friend's split> else 0 end)
             - (case when paid_by = friend then <my split>       else 0 end)
```

Per-group settlement / direct-settlement net (mirrors the two settlement
terms of `get_friend_balance`):

```
net(settlement) = (case when from_user = me     then amount else 0 end)   -- I paid the friend
                - (case when from_user = friend then amount else 0 end)    -- the friend paid me
```

The sum of every returned row's `net` therefore equals
`get_friend_balance(me, friend)` exactly.

## New RPC: `get_friend_activity(other_user uuid)`

`SECURITY DEFINER`, `set search_path = public`, `stable`, granted to
`authenticated`, revoked from `public` — same pattern as
`get_shared_expenses` / `get_friend_balance`. It needs `SECURITY
DEFINER` because it reads splits, group memberships, group names, and
settlements that RLS may hide from the caller when the counterparty is
the payer/creator; every returned row is nonetheless constrained to the
me↔friend relationship, so the caller can only ever see their own
activity.

Returns `setof` rows shaped as:

| column          | type    | meaning                                             |
|-----------------|---------|-----------------------------------------------------|
| `kind`          | text    | `'expense'` \| `'group'` \| `'settlement'`          |
| `ref_id`        | uuid    | expense id / group id / settlement id               |
| `name`          | text    | description / group name / `'Payment'`              |
| `net`           | numeric | signed net for the caller (see sign convention)     |
| `activity_date` | date    | expense_date / latest group activity / settled date |

Row sources (`me := auth.uid()`, `friend := other_user`):

1. **Direct expenses** — `expenses` where `deleted_at is null`,
   `group_id is null`, and the pair predicate from the earlier
   `get_shared_expenses` fix holds (I paid & friend has a split, OR
   friend paid & I have a split). One row per expense, `kind='expense'`,
   `net` from the per-expense formula, `activity_date = expense_date`.

2. **Shared groups** — every group where both `me` and `friend` are in
   `group_members`. One row per group, `kind='group'`, `name = groups.name`,
   `net =` sum of the per-expense formula over that group's non-deleted
   expenses **plus** the settlement term over confirmed settlements in
   that group between the pair. `activity_date =` greatest of the group's
   latest non-deleted `expense_date` and latest confirmed settlement date
   (null-safe; falls back to a stable value if the group is empty).
   Emitted even when `net = 0` so "Show settled" can display it.

3. **Direct settlements** — confirmed `settlements` where
   `group_id is null` and `{from_user, to_user} = {me, friend}`. One row
   per settlement, `kind='settlement'`, `name='Payment'`, `net` from the
   settlement formula, `activity_date = coalesce(confirmed_at::date,
   created_at::date)`.

Ordering is left to the client (needs the full set to interleave the
three kinds), but the RPC may return in any order.

### Reconciliation guarantee

`sum(net)` over all rows `= get_friend_balance(me, friend)`:
- direct-expense rows cover the expense terms for `group_id is null`;
- group rows cover the expense terms for each `group_id` plus in-group
  settlement terms;
- direct-settlement rows cover the remaining settlement terms.
Together these partition exactly the same underlying rows the two RPCs
sum, with no overlap and no omission.

## Client changes — `FriendDetailScreen`

- Add `getFriendActivity(String otherUserId)` to `ExpenseRepository`
  (calls the RPC, maps rows to a small `FriendActivityItem` model:
  `kind`, `refId`, `name`, `net`, `date`). Sorts newest-first.
- Replace the inner `FutureBuilder<List<Expense>>` +
  `getSharedExpenses` block with a `FutureBuilder<List<FriendActivityItem>>`
  on the new method.
- Render:
  - Hide items where `net == 0` unless the local "Show settled" toggle is
    on. Toggle is a small text button below the header (only shown when
    there is at least one settled item to reveal).
  - Each row: leading icon (group icon for `kind='group'`, receipt icon
    otherwise), `name`, and a right-aligned coloured amount using the
    existing balance colour convention — reuse `BalanceAmount` if it fits,
    else a small local widget rendering "you owe ₹X" / "you lent ₹X".
  - Tap: `expense` → `ExpenseDetailScreen` (fetch the `Expense` by
    `ref_id`, or navigate with the id); `group` → `GroupDetailScreen(groupId: ref_id)`;
    `settlement` → not tappable.
  - Empty state unchanged when there are no (visible) items.
- `ExpenseDetailScreen` currently takes an `Expense` object. The activity
  row only carries an id, so either (a) add a lightweight
  `getExpenseById` and navigate with the fetched `Expense`, or (b) keep
  `get_friend_activity` returning enough expense fields — decided in the
  plan; (a) is preferred to keep the RPC's return shape flat.

## Testing

- **DB**: extend `supabase/tests/database/run_balance_rpc_tests.sh` with
  authenticated-role cases asserting, against the existing Alex/Sam/Priya
  fixtures:
  - a direct-expense row, a group row (Trip), and a direct-settlement row
    are returned with the correct `kind`, `name`, and `net`;
  - the Trip group row's `net` equals the pairwise Alex↔Sam net within
    that group (not the simplified group debt);
  - `sum(net)` over all rows equals `get_friend_balance(Alex, Sam)`
    (the reconciliation guarantee).
- **Dart**: a repository test that `getFriendActivity` calls the RPC and
  maps/sorts rows; a widget test that settled (`net == 0`) rows are hidden
  until the toggle is pressed.

## Superseded / cleanup

The earlier migration
`20260728120100_get_shared_expenses.sql` + its fix
`20260728130000_get_shared_expenses_include_groups.sql` and
`ExpenseRepository.getSharedExpenses` become unused once Friend Detail
switches to `get_friend_activity`. Leave the migrations in place
(forward-only history; harmless) but remove the now-dead
`getSharedExpenses` call site. Whether to also delete the method is a
plan-time call.

## Out of scope

- Month/date section headers (Splitwise groups rows by month).
- A settlement detail screen (settlement rows stay non-tappable).
- Changing the home screen or group screens.
