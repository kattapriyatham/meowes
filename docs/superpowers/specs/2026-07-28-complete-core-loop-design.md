# Complete the core expense-splitting loop — design

Follow-up to the screen-by-screen audit run after the restyle plan: several
repository methods already exist (`acceptFriendRequest`, `joinByInviteCode`,
`confirmSettlement`, `watchPendingForMe`) but nothing in the UI ever calls
them, and `ExpenseDetailScreen`/editing an expense are effectively dead
code. This spec covers the five gaps decided in scope (Group A + B from the
audit): Friend Requests, Join Group by Code, Fix Expense Editing, Expense
History, and the shared Notifications surface that ties two of them
together. Explicitly out of scope for this spec: Activity feed,
Profile/Settings screen, push notifications (Group C from the audit).

## 1. Notifications screen (Friend Requests + Settlement Confirmations)

**Trigger:** Home's bell icon (`lib/features/home/home_screen.dart`,
`_GreetingHeader`) currently has no `onTap`. It gets one, pushing
`NotificationsScreen`.

**Data — no new queries for the friend-request half:**
`FriendRepository.watchFriendships()` already streams every friendship row
the current user is party to, regardless of status. `NotificationsScreen`
filters that same stream client-side for
`status == FriendshipStatus.pending && requestedBy != me` — these are
requests sent *to* me, awaiting my decision. (Requests I sent *to* others
stay invisible here, matching Add Friend's existing behavior of not
tracking sent-request state.)

**Data — no new queries for the settlement half:**
`SettlementRepository.watchPendingForMe()` already exists and already
returns settlements where `to_user = me` and `status = 'pending_confirmation'`
— exactly "settlements someone else marked paid that I need to confirm."

**New repository method:** `FriendRepository.declineFriendRequest(String
fromUserId)` — deletes the friendship row. Needs a new RLS delete policy;
`friendships` currently has no delete policy at all (confirmed: only
`friendships_select_party`, `friendships_insert_party`,
`friendships_update_party` exist). New migration:

```sql
create policy friendships_delete_party on friendships
  for delete to authenticated using (
    auth.uid() = user_id_a or auth.uid() = user_id_b
  );
```

Accepting still uses `FriendRepository.acceptFriendRequest`. Confirming
still uses `SettlementRepository.confirmSettlement`.

**Screen layout:** two sections, "Friend requests" and "Settlements to
confirm," each an `AppCard` list (or `EmptyStateBox` if empty). A friend
request row shows the requester's name (via `getPublicProfiles`) with
Accept/Decline buttons. A settlement row shows who paid and how much, with
a single Confirm button.

**Empty state:** if both lists are empty, the whole screen is one
`EmptyStateBox` ("Nothing needs your attention right now").

## 2. Join Group by Code

`CreateGroupScreen` (`lib/features/groups/create_group_screen.dart`) gets a
two-tab/segmented toggle at the top: "Create" (existing form, unchanged)
and "Join" (new — a single text field for the invite code plus a button
calling the already-existing `GroupRepository.joinByInviteCode(code)`).
On success, joining pops back to Home the same way a create does (existing
`createGroup` success path already pops with the new `Group`; join mirrors
that). No backend changes — `joinByInviteCode` and its RPC already exist
and are already tested (`test/repositories/group_repository_test.dart`
covers the invalid-code case).

## 3. Fix Expense Editing

**Current state (confirmed by grep):** `ExpenseRepository.editExpense`
only updates `description`/`amount`/`edited_at`/`edited_by` — it never
touches `expense_splits`. The code comment claiming re-splitting happens
elsewhere is wrong; nothing calls `editExpense` from any screen today.
`ExpenseDetailScreen`'s Edit button pushes `AddExpenseScreen` with
`participantIds: const []`, which (after this session's Task 9 fix) means
Add Expense now shows a graceful "no participants" message instead of
crashing — but editing an expense has never actually worked.

**Repository changes:**
- Extend `editExpense` to accept the same split-related parameters
  `createExpense` does: `required SplitType splitType`, `required
  List<String> participantIds`, `Map<String, double>? percentages`,
  `Map<String, int>? exactAmounts`. After updating the `expenses` row, it
  deletes the expense's existing `expense_splits` rows and inserts new ones
  via `SplitCalculator.calculate` — the same insert logic `createExpense`
  already uses (extract a private `_writeSplits(expenseId, ...)` helper
  shared by both methods to avoid duplicating that block).
- New method: `Future<List<ExpenseSplit>> getExpenseSplits(String
  expenseId)` — a plain `.from('expense_splits').select().eq('expense_id',
  expenseId)`, existing RLS on `expense_splits` already permits this for
  anyone who can see the parent expense.

**Screen changes:**
- `AddExpenseScreen` gets an optional `Expense? editing` constructor
  param. When present: `initState` prefills `_descriptionController`,
  `_amountController`, `_paidBy` from the `Expense`, and fetches its splits
  via `getExpenseSplits` to prefill `_splitType`/percentages/exact amounts
  (equal split needs no prefill beyond participants; percentage/exact
  derive their per-participant values from the fetched `ExpenseSplit`
  amounts). The Save button calls `editExpense` instead of `createExpense`
  when `editing != null`, and the AppBar title reads "Edit expense".
- `ExpenseDetailScreen`'s Edit button passes `AddExpenseScreen(editing:
  expense, groupId: expense.groupId, participantIds: <ids from splits>)` —
  the participant IDs now come from the real `getExpenseSplits` call
  (fetched once in `ExpenseDetailScreen`'s own `initState` equivalent, a
  `FutureBuilder`) instead of the `const []` stub.

**Known limitation, not fixed by this spec:** `expense_splits` RLS
(`expense_splits_select_participant`) only lets a caller see every
participant's split when they're the expense's payer/creator (or a
group member); a participant who is neither will only see their own row
via `getExpenseSplits`, so editing an expense you only participated in
(not created or paid) will prefill incompletely. This mirrors the existing
`expenses_update_participant` RLS policy, which already lets any
participant attempt an edit — that permission scope isn't something this
spec changes, just something the new Edit flow inherits. Worth a follow-up
if it turns out to matter in practice.

## 4. Expense History + Reachable Expense Detail

This is what finally makes `ExpenseDetailScreen` reachable from real
navigation (confirmed by grep: nothing constructs it today).

**Group Detail:** new `ExpenseRepository.watchExpenses({required String
groupId})` — `.from('expenses').stream(primaryKey: ['id']).eq('group_id',
groupId)`, filtered client-side for `deletedAt == null` and ordered by
`expenseDate` descending. No new backend — existing RLS on `expenses`
already permits group members to select. Rendered as an "Expenses"
section (new `AppCard` list) on `GroupDetailScreen`, above "Smart settle
suggestions," each row tappable into `ExpenseDetailScreen(expense: e)`.

**Friend Detail:** direct (non-group) expenses between exactly two people
aren't expressible as a single-table `.eq()` filter the way group expenses
are (need "no group AND both people involved"), so this one needs a new
RPC, same pattern as the existing `get_friend_balance`:

```sql
create or replace function get_shared_expenses(other_user uuid)
returns setof expenses
language sql
security definer
set search_path = public
stable
as $$
  select e.* from expenses e
  where e.deleted_at is null
    and e.group_id is null
    and (e.paid_by = auth.uid() or e.paid_by = other_user)
    and exists (
      select 1 from expense_splits es
      where es.expense_id = e.id and es.user_id = other_user
    )
    and exists (
      select 1 from expense_splits es
      where es.expense_id = e.id and es.user_id = auth.uid()
    );
$$;

revoke all on function get_shared_expenses(uuid) from public;
grant execute on function get_shared_expenses(uuid) to authenticated;
```

Must be `security definer`, not `security invoker`: when `other_user` is
the payer (not `auth.uid()`), the `exists` check against
`expense_splits.user_id = other_user` runs on a non-group expense the
caller neither paid nor created, which `expense_splits_select_participant`'s
RLS would normally hide from them — an invoker-security function would
silently under-return real shared expenses in exactly that case. Bypassing
RLS here is safe because the query's own two `exists` clauses already
constrain every returned row to one where *both* `auth.uid()` and
`other_user` have a split — a caller can never get back an expense they
weren't actually part of, mirroring the same reasoning already used for
`is_group_member`/`is_expense_owner` elsewhere in this codebase. New
repository method: `Future<List<Expense>> getSharedExpenses(String
otherUserId)` calling this RPC. Rendered the same way as Group Detail's
list, on `FriendDetailScreen`.

Group expenses between two friends are intentionally excluded from this
list (scoped to `group_id is null`) — those already show up in the
relevant Group Detail screen, and mixing the two would double-count/
confuse "this friend's direct history" with "shared group history."

## Testing

- `SplitCalculator`/`ExpenseRepository` changes: extend
  `test/repositories/expense_repository_test.dart` with a case for
  `editExpense` actually replacing splits (mock the delete+insert calls,
  assert the new splits match a recalculated `SplitCalculator` output).
- `declineFriendRequest`: mirror the existing `sendFriendRequest` test
  pattern in `test/repositories/friend_repository_test.dart`.
- No widget-level tests are added for the three new/changed screens
  (`NotificationsScreen`, the Create/Join toggle, expense history lists) —
  consistent with this codebase's existing convention of repository-level
  tests plus the two pre-existing widget tests (Home, Expense Detail),
  neither of which this spec's changes touch in a way that breaks their
  assertions.
- Both new migrations get a quick manual verification against the live
  linked Supabase project (same pattern used earlier this session for the
  `get_group_debts` and realtime-publication fixes) before being considered
  done.
