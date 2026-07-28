# Friend Detail Activity List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Friend Detail's flat expense list with a Splitwise-style activity list where each row is a direct expense, a shared group (by name), or a payment, showing the current user's colour-coded net for that row, and where the rows reconcile to the header balance.

**Architecture:** A single `SECURITY DEFINER` RPC `get_friend_activity(other_user)` decomposes the same math as `get_friend_balance` into per-row buckets (direct expenses individually, groups aggregated, direct settlements individually). The Flutter side maps these rows into a `FriendActivityItem` model and renders them, hiding `net == 0` rows behind a "Show settled" toggle.

**Tech Stack:** Postgres (Supabase migrations + `supabase db push`/`db query --linked`), Dart/Flutter, Riverpod, mocktail for tests.

## Global Constraints

- Migrations are forward-only: add a new timestamped file under `supabase/migrations/`, never edit an applied one. Use the `YYYYMMDDHHMMSS_name.sql` format.
- New DB functions follow the existing pattern: `security definer`, `set search_path = public`, `stable`, `revoke all ... from public`, `grant execute ... to authenticated`.
- Sign convention (matches `get_friend_balance(me, friend)`): `net > 0` = the friend owes me; `net < 0` = I owe the friend.
- Money is stored as `numeric(12,2)` rupees in the DB; the Dart `Expense` model uses `amountMinorUnits` (paise). Activity `net` stays in rupees as a `double` (it is only displayed, never re-split).
- DB tests run against the linked cloud project via `supabase db query --linked`; functions that read `auth.uid()` must be tested under `set local role authenticated; set local request.jwt.claim.sub = '<uuid>'`.
- Currency symbol is `₹`; reuse the existing `BalanceAmount` widget for coloured amounts.

---

### Task 1: `get_friend_activity` RPC + database tests

**Files:**
- Create: `supabase/migrations/20260728140000_get_friend_activity.sql`
- Modify: `supabase/tests/database/run_balance_rpc_tests.sh` (append cases before the final `echo "$pass_count passed..."`)

**Interfaces:**
- Consumes: existing tables `expenses`, `expense_splits`, `groups`, `group_members`, `settlements`; existing function `get_friend_balance(uuid, uuid)`.
- Produces: `get_friend_activity(other_user uuid) returns table(kind text, ref_id uuid, name text, net numeric, activity_date date)`. `kind` ∈ `{'expense','group','settlement'}`. Called from Dart as `client.rpc('get_friend_activity', params: {'other_user': <id>})`.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260728140000_get_friend_activity.sql`:

```sql
-- Friend Detail's activity list. Decomposes the exact math of
-- get_friend_balance(me, friend) into displayable rows so the list
-- reconciles to the header balance:
--   * direct expenses (group_id is null)  -> one row each
--   * shared groups (both are members)    -> one aggregated row each
--   * direct settlements (group_id null)  -> one row each ("Payment")
-- Sign convention matches get_friend_balance: net > 0 => friend owes me,
-- net < 0 => I owe the friend.
--
-- SECURITY DEFINER: reads splits, group names, memberships and
-- settlements that RLS may hide from the caller when the counterparty is
-- the payer/creator. Safe because every row is constrained to the
-- me(auth.uid())<->other_user relationship, so a caller only ever sees
-- their own activity.
create or replace function get_friend_activity(other_user uuid)
returns table(kind text, ref_id uuid, name text, net numeric, activity_date date)
language sql
security definer
set search_path = public
stable
as $$
  -- 1. Direct (non-group) expenses, one row each.
  select 'expense'::text as kind,
         e.id as ref_id,
         e.description as name,
         (
           (case when e.paid_by = auth.uid() then coalesce(
              (select es.share_amount from expense_splits es
               where es.expense_id = e.id and es.user_id = other_user), 0) else 0 end)
         - (case when e.paid_by = other_user then coalesce(
              (select es.share_amount from expense_splits es
               where es.expense_id = e.id and es.user_id = auth.uid()), 0) else 0 end)
         )::numeric as net,
         e.expense_date as activity_date
  from expenses e
  where e.deleted_at is null
    and e.group_id is null
    and (
      (e.paid_by = auth.uid() and exists (
         select 1 from expense_splits es where es.expense_id = e.id and es.user_id = other_user))
      or
      (e.paid_by = other_user and exists (
         select 1 from expense_splits es where es.expense_id = e.id and es.user_id = auth.uid()))
    )

  union all

  -- 2. Shared groups (both are members), one aggregated row each.
  select 'group'::text as kind,
         g.id as ref_id,
         g.name as name,
         (
           coalesce((
             select sum(
               (case when e.paid_by = auth.uid() then coalesce(
                  (select es.share_amount from expense_splits es
                   where es.expense_id = e.id and es.user_id = other_user), 0) else 0 end)
             - (case when e.paid_by = other_user then coalesce(
                  (select es.share_amount from expense_splits es
                   where es.expense_id = e.id and es.user_id = auth.uid()), 0) else 0 end)
             )
             from expenses e
             where e.group_id = g.id and e.deleted_at is null
           ), 0)
           + coalesce((
             select sum(case when s.from_user = auth.uid() then s.amount
                             when s.from_user = other_user then -s.amount
                             else 0 end)
             from settlements s
             where s.group_id = g.id and s.status = 'confirmed'
               and ((s.from_user = auth.uid() and s.to_user = other_user)
                 or (s.from_user = other_user and s.to_user = auth.uid()))
           ), 0)
         )::numeric as net,
         greatest(
           coalesce((select max(e.expense_date) from expenses e
                     where e.group_id = g.id and e.deleted_at is null), 'epoch'::date),
           coalesce((select max(coalesce(s.confirmed_at::date, s.created_at::date))
                     from settlements s
                     where s.group_id = g.id and s.status = 'confirmed'
                       and ((s.from_user = auth.uid() and s.to_user = other_user)
                         or (s.from_user = other_user and s.to_user = auth.uid()))),
                    'epoch'::date)
         ) as activity_date
  from groups g
  where exists (select 1 from group_members gm where gm.group_id = g.id and gm.user_id = auth.uid())
    and exists (select 1 from group_members gm where gm.group_id = g.id and gm.user_id = other_user)

  union all

  -- 3. Direct (non-group) confirmed settlements between the pair, one row each.
  select 'settlement'::text as kind,
         s.id as ref_id,
         'Payment'::text as name,
         (case when s.from_user = auth.uid() then s.amount else -s.amount end)::numeric as net,
         coalesce(s.confirmed_at::date, s.created_at::date) as activity_date
  from settlements s
  where s.group_id is null
    and s.status = 'confirmed'
    and ((s.from_user = auth.uid() and s.to_user = other_user)
      or (s.from_user = other_user and s.to_user = auth.uid()));
$$;

revoke all on function get_friend_activity(uuid) from public;
grant execute on function get_friend_activity(uuid) to authenticated;
```

- [ ] **Step 2: Append database test cases**

In `supabase/tests/database/run_balance_rpc_tests.sh`, immediately before the final `echo "$pass_count passed, $fail_count failed"` line, add:

```bash
# get_friend_activity must decompose get_friend_balance into displayable
# rows. Reads auth.uid(), so run under the authenticated role like the
# other RLS-sensitive checks. Using the existing Alex/Sam/Priya fixtures:
#   EXPENSE1        - direct, Alex paid 1000, split 500/500  -> Sam owes Alex 500
#   EXPENSE_SAM_PAID - direct, Sam paid 300, split 150/150   -> Alex owes Sam 150
#   EXPENSE2        - GROUP (Trip), Alex paid 300, 100 each  -> Sam owes Alex 100 pairwise
#   settlements: Sam->Alex 500 (direct), Alex->Sam 200 (direct),
#                Sam->Alex 100 (group Trip)
activity_json=$(supabase db query --linked --output-format json "
  set local role authenticated;
  set local request.jwt.claim.sub = '$ALEX';
  select
    (select count(*)::int from get_friend_activity('$SAM') where kind = 'expense')    as expenses,
    (select count(*)::int from get_friend_activity('$SAM') where kind = 'group')      as groups,
    (select count(*)::int from get_friend_activity('$SAM') where kind = 'settlement') as settlements,
    (select net from get_friend_activity('$SAM') where kind = 'group' and ref_id = '$TRIP_GROUP') as trip_net,
    (select round(sum(net), 2) from get_friend_activity('$SAM')) as total,
    get_friend_balance('$ALEX', '$SAM') as balance;
")
a_exp=$(echo "$activity_json" | jq -r '.rows[0].expenses // "null"')
a_grp=$(echo "$activity_json" | jq -r '.rows[0].groups // "null"')
a_set=$(echo "$activity_json" | jq -r '.rows[0].settlements // "null"')
a_trip=$(echo "$activity_json" | jq -r '.rows[0].trip_net // "null"')
a_total=$(echo "$activity_json" | jq -r '.rows[0].total // "null"')
a_balance=$(echo "$activity_json" | jq -r '.rows[0].balance // "null"')

if [[ "$a_exp" == "2" && "$a_grp" == "1" && "$a_set" == "2" ]]; then
  echo "ok - get_friend_activity returns 2 direct expenses, 1 group row, 2 direct settlements"
  pass_count=$((pass_count + 1))
else
  echo "not ok - get_friend_activity row kinds (expenses: $a_exp, groups: $a_grp, settlements: $a_set)"
  fail_count=$((fail_count + 1))
fi

# Trip group row must reflect the pairwise Alex<->Sam net inside the group
# (Alex paid 300 split 100 each => Sam owes Alex 100; group settlement
# Sam->Alex 100 clears it), NOT the simplified group debt.
if [[ "$a_trip" == "0.00" || "$a_trip" == "0" ]]; then
  echo "ok - get_friend_activity Trip group row nets the in-group pairwise balance to 0"
  pass_count=$((pass_count + 1))
else
  echo "not ok - get_friend_activity Trip group net (actual: $a_trip, expected 0)"
  fail_count=$((fail_count + 1))
fi

# Reconciliation: the rows must sum to the header balance exactly.
if [[ "$a_total" == "$a_balance" ]]; then
  echo "ok - get_friend_activity rows sum to get_friend_balance ($a_total)"
  pass_count=$((pass_count + 1))
else
  echo "not ok - get_friend_activity reconciliation (sum: $a_total, balance: $a_balance)"
  fail_count=$((fail_count + 1))
fi
```

- [ ] **Step 3: Run the suite to verify the new cases fail (function not yet deployed)**

Run: `bash supabase/tests/database/run_balance_rpc_tests.sh 2>&1 | grep -vE "Initialising|Connecting"`
Expected: the three new `get_friend_activity` lines are `not ok` (the function does not exist yet, so the query errors and the vars are `null`). Existing 9 lines still `ok`.

- [ ] **Step 4: Deploy the migration**

Run: `supabase db push --linked`
Expected: `Applying migration 20260728140000_get_friend_activity.sql...` then `Finished supabase db push.` (a Docker catalog-cache warning is benign).

- [ ] **Step 5: Run the suite to verify all cases pass**

Run: `bash supabase/tests/database/run_balance_rpc_tests.sh 2>&1 | grep -vE "Initialising|Connecting"`
Expected: `12 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260728140000_get_friend_activity.sql supabase/tests/database/run_balance_rpc_tests.sh
git commit -m "Add get_friend_activity RPC decomposing friend balance into activity rows"
```

---

### Task 2: `FriendActivityItem` model + repository methods

**Files:**
- Create: `lib/models/friend_activity_item.dart`
- Modify: `lib/repositories/expense_repository.dart` (add `getFriendActivity`, `getExpenseById`)
- Create: `test/models/friend_activity_item_test.dart`
- Modify: `test/repositories/expense_repository_test.dart` (add `getFriendActivity` mapping/sort test)

**Interfaces:**
- Consumes: `get_friend_activity` RPC from Task 1; existing `Expense.fromJson`.
- Produces:
  - `enum FriendActivityKind { expense, group, settlement }`
  - `class FriendActivityItem { final FriendActivityKind kind; final String refId; final String name; final double net; final DateTime date; FriendActivityItem.fromJson(Map<String,dynamic>); }`
  - `Future<List<FriendActivityItem>> ExpenseRepository.getFriendActivity(String otherUserId)` — returns items sorted newest-first.
  - `Future<Expense> ExpenseRepository.getExpenseById(String expenseId)`.

- [ ] **Step 1: Write the model test**

Create `test/models/friend_activity_item_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowes_app/models/friend_activity_item.dart';

void main() {
  test('FriendActivityItem.fromJson parses kind, net (numeric) and date', () {
    final item = FriendActivityItem.fromJson({
      'kind': 'group',
      'ref_id': 'g1',
      'name': 'Goa Trip',
      'net': -1400.00,
      'activity_date': '2026-07-20',
    });
    expect(item.kind, FriendActivityKind.group);
    expect(item.refId, 'g1');
    expect(item.name, 'Goa Trip');
    expect(item.net, -1400.00);
    expect(item.date, DateTime(2026, 7, 20));
  });

  test('FriendActivityItem.fromJson accepts net as a string (PostgREST numeric wire format)', () {
    final item = FriendActivityItem.fromJson({
      'kind': 'expense',
      'ref_id': 'e1',
      'name': 'Groceries',
      'net': '100.00',
      'activity_date': '2026-07-27',
    });
    expect(item.kind, FriendActivityKind.expense);
    expect(item.net, 100.00);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/models/friend_activity_item_test.dart`
Expected: FAIL — `friend_activity_item.dart` does not exist.

- [ ] **Step 3: Write the model**

Create `lib/models/friend_activity_item.dart`:

```dart
enum FriendActivityKind { expense, group, settlement }

/// One row in a friend's activity list. [net] follows get_friend_balance's
/// sign convention: net > 0 means the friend owes the signed-in user,
/// net < 0 means the signed-in user owes the friend.
class FriendActivityItem {
  final FriendActivityKind kind;
  final String refId;
  final String name;
  final double net;
  final DateTime date;

  FriendActivityItem({
    required this.kind,
    required this.refId,
    required this.name,
    required this.net,
    required this.date,
  });

  factory FriendActivityItem.fromJson(Map<String, dynamic> json) {
    final rawNet = json['net'];
    final net = rawNet is num ? rawNet.toDouble() : double.parse(rawNet.toString());
    return FriendActivityItem(
      kind: FriendActivityKind.values.byName(json['kind'] as String),
      refId: json['ref_id'] as String,
      name: json['name'] as String,
      net: net,
      date: DateTime.parse(json['activity_date'] as String),
    );
  }
}
```

- [ ] **Step 4: Run the model test to verify it passes**

Run: `flutter test test/models/friend_activity_item_test.dart`
Expected: PASS (both tests).

- [ ] **Step 5: Write the repository test**

The existing tests in this file each construct their own `client`/`repo`
inline (there is no shared `setUp`), and `client.rpc(...)` returns a
`Future` directly so it can be stubbed with a plain `thenAnswer` — no
Fake builder needed. Add the import at the top of the file:

```dart
import 'package:meowes_app/models/friend_activity_item.dart';
```

Then add this self-contained test inside `main()`:

```dart
test('getFriendActivity calls the RPC and returns items sorted newest-first', () async {
  final client = MockSupabaseClient();
  when(() => client.rpc('get_friend_activity',
          params: {'other_user': 'friend-1'}))
      .thenAnswer((_) async => [
            {'kind': 'expense', 'ref_id': 'e1', 'name': 'Old', 'net': 100.0, 'activity_date': '2026-07-01'},
            {'kind': 'group', 'ref_id': 'g1', 'name': 'Trip', 'net': -50.0, 'activity_date': '2026-07-20'},
          ]);

  final repo = ExpenseRepository(client);
  final items = await repo.getFriendActivity('friend-1');

  expect(items.length, 2);
  expect(items.first.name, 'Trip'); // newest first
  expect(items.last.name, 'Old');
  expect(items.first.kind, FriendActivityKind.group);
});
```

- [ ] **Step 6: Run the repository test to verify it fails**

Run: `flutter test test/repositories/expense_repository_test.dart`
Expected: FAIL — `getFriendActivity` is not defined on `ExpenseRepository`.

- [ ] **Step 7: Implement the repository methods**

In `lib/repositories/expense_repository.dart`, add the import at the top:

```dart
import 'package:meowes_app/models/friend_activity_item.dart';
```

Add these methods to the `ExpenseRepository` class (next to `getSharedExpenses`):

```dart
Future<List<FriendActivityItem>> getFriendActivity(String otherUserId) async {
  final rows = await _client.rpc('get_friend_activity', params: {'other_user': otherUserId});
  final results = rows is List<dynamic> ? rows : const <dynamic>[];
  final items = results
      .map((r) => FriendActivityItem.fromJson(r as Map<String, dynamic>))
      .toList();
  items.sort((a, b) => b.date.compareTo(a.date));
  return items;
}

Future<Expense> getExpenseById(String expenseId) async {
  final row = await _client.from('expenses').select().eq('id', expenseId).single();
  return Expense.fromJson(row);
}
```

- [ ] **Step 8: Run the repository test to verify it passes**

Run: `flutter test test/repositories/expense_repository_test.dart`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add lib/models/friend_activity_item.dart lib/repositories/expense_repository.dart test/models/friend_activity_item_test.dart test/repositories/expense_repository_test.dart
git commit -m "Add FriendActivityItem model and getFriendActivity/getExpenseById repository methods"
```

---

### Task 3: Friend Detail activity list UI + toggle

**Files:**
- Modify: `lib/features/friends/friend_detail_screen.dart`
- Create: `test/features/friends/friend_detail_screen_test.dart`

**Interfaces:**
- Consumes: `ExpenseRepository.getFriendActivity` and `getExpenseById` (Task 2); `FriendActivityItem`/`FriendActivityKind` (Task 2); existing `BalanceAmount`, `AppCard`, `EmptyStateBox`, `SectionHeader` widgets; `GroupDetailScreen(groupId:)`, `ExpenseDetailScreen(expense:)`.
- Produces: no new public API; replaces the inner expense-history section.

- [ ] **Step 1: Write the widget test**

Create `test/features/friends/friend_detail_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart';
import 'package:meowes_app/features/friends/friend_detail_screen.dart';
import 'package:meowes_app/models/friend_activity_item.dart';
import 'package:meowes_app/repositories/expense_repository.dart';
import 'package:meowes_app/repositories/friend_repository.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockGoTrueClient extends Mock implements GoTrueClient {}
class MockExpenseRepository extends Mock implements ExpenseRepository {}
class MockFriendRepository extends Mock implements FriendRepository {}

void main() {
  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());

  testWidgets('settled (net==0) rows are hidden until Show settled is tapped', (tester) async {
    final mockClient = MockSupabaseClient();
    final mockAuth = MockGoTrueClient();
    final mockExpenseRepo = MockExpenseRepository();
    final mockFriendRepo = MockFriendRepository();

    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(User(
      id: 'me', appMetadata: const {}, userMetadata: const {},
      aud: 'authenticated', createdAt: '2026-07-27T00:00:00Z',
    ));
    when(() => mockClient.rpc('get_friend_balance',
        params: {'user_a': 'me', 'user_b': 'friend-1'})).thenAnswer((_) async => -100.0);
    when(() => mockFriendRepo.getPublicProfiles(['friend-1'])).thenAnswer((_) async => []);
    when(() => mockExpenseRepo.getFriendActivity('friend-1')).thenAnswer((_) async => [
      FriendActivityItem(kind: FriendActivityKind.group, refId: 'g1', name: 'Goa Trip', net: -100.0, date: DateTime(2026, 7, 20)),
      FriendActivityItem(kind: FriendActivityKind.group, refId: 'g2', name: 'Flatmates', net: 0.0, date: DateTime(2026, 7, 10)),
    ]);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        supabaseClientProvider.overrideWithValue(mockClient),
        expenseRepositoryProvider.overrideWithValue(mockExpenseRepo),
        friendRepositoryProvider.overrideWithValue(mockFriendRepo),
      ],
      child: const MaterialApp(home: FriendDetailScreen(friendUserId: 'friend-1')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Goa Trip'), findsOneWidget);
    expect(find.text('Flatmates'), findsNothing); // net 0 hidden

    await tester.tap(find.text('Show settled'));
    await tester.pumpAndSettle();

    expect(find.text('Flatmates'), findsOneWidget); // now visible
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/friends/friend_detail_screen_test.dart`
Expected: FAIL — `getFriendActivity` is not yet used; no "Show settled" control; likely a mock error on the old `getSharedExpenses` stub path.

- [ ] **Step 3: Replace the expense-history section with the activity list**

In `lib/features/friends/friend_detail_screen.dart`:

1. Update imports — remove `import 'package:meowes_app/models/expense.dart';` if it becomes unused, add:

```dart
import 'package:meowes_app/features/groups/group_detail_screen.dart';
import 'package:meowes_app/models/friend_activity_item.dart';
```

(Keep the `expense_detail_screen.dart`, `add_friend_screen.dart`, `app_user.dart`, `app_theme.dart` imports.)

2. Replace the `SectionHeader(title: 'Expense history')` + its following `FutureBuilder<List<Expense>>(...)` block (everything from the `const SectionHeader(title: 'Expense history')` line through its closing `),` before the end of the `ListView` children) with a single widget instance:

```dart
                _FriendActivitySection(friendUserId: friendUserId),
```

3. At the bottom of the file (after the `FriendDetailScreen` class), add the section widget. It is a `ConsumerStatefulWidget` so it can hold the `_showSettled` toggle:

```dart
class _FriendActivitySection extends ConsumerStatefulWidget {
  final String friendUserId;
  const _FriendActivitySection({required this.friendUserId});

  @override
  ConsumerState<_FriendActivitySection> createState() => _FriendActivitySectionState();
}

class _FriendActivitySectionState extends ConsumerState<_FriendActivitySection> {
  bool _showSettled = false;

  bool _isSettled(FriendActivityItem i) => i.net.abs() < 0.005;

  Future<void> _openItem(BuildContext context, FriendActivityItem item) async {
    switch (item.kind) {
      case FriendActivityKind.group:
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => GroupDetailScreen(groupId: item.refId),
        ));
        break;
      case FriendActivityKind.expense:
        final expense = await ref.read(expenseRepositoryProvider).getExpenseById(item.refId);
        if (!context.mounted) return;
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ExpenseDetailScreen(expense: expense),
        ));
        break;
      case FriendActivityKind.settlement:
        break; // no detail screen for settlements
    }
  }

  @override
  Widget build(BuildContext context) {
    final expenseRepo = ref.watch(expenseRepositoryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Activity'),
        const SizedBox(height: 12),
        FutureBuilder<List<FriendActivityItem>>(
          future: expenseRepo.getFriendActivity(widget.friendUserId),
          builder: (context, snapshot) {
            final all = snapshot.data ?? [];
            final hasSettled = all.any(_isSettled);
            final visible = _showSettled ? all : all.where((i) => !_isSettled(i)).toList();

            if (all.isEmpty) {
              return const EmptyStateBox(
                icon: Icons.receipt_long_outlined,
                message: 'No activity with this friend yet.',
              );
            }
            return Column(
              children: [
                if (visible.isEmpty)
                  const EmptyStateBox(
                    icon: Icons.check_circle_outline,
                    message: 'All settled with this friend.',
                  ),
                for (final item in visible) ...[
                  AppCard(
                    onTap: item.kind == FriendActivityKind.settlement
                        ? null
                        : () => _openItem(context, item),
                    child: Row(
                      children: [
                        Icon(
                          item.kind == FriendActivityKind.group
                              ? Icons.groups
                              : (item.kind == FriendActivityKind.settlement
                                  ? Icons.swap_horiz
                                  : Icons.receipt_long_outlined),
                          color: AppColors.coral,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            item.name,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ),
                        BalanceAmount(balance: item.net),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (hasSettled)
                  Align(
                    alignment: Alignment.center,
                    child: TextButton(
                      onPressed: () => setState(() => _showSettled = !_showSettled),
                      child: Text(_showSettled ? 'Hide settled' : 'Show settled'),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
```

Note: `BalanceAmount` renders `net > 0` green `+₹X`, `net < 0` red `-₹X`, and `Settled` when ~0 — matching the app's existing friend/group rows.

- [ ] **Step 4: Run the widget test to verify it passes**

Run: `flutter test test/features/friends/friend_detail_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Remove the now-dead `getSharedExpenses` call site**

Confirm `getSharedExpenses` is no longer referenced by any screen:

Run: `grep -rn "getSharedExpenses" lib/`
Expected: no matches (the only caller was Friend Detail). Leave the repository method and its migration in place (forward-only history; harmless), but remove any now-unused imports in `friend_detail_screen.dart` flagged by analyze.

- [ ] **Step 6: Analyze and run the full suite**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` and all tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/features/friends/friend_detail_screen.dart test/features/friends/friend_detail_screen_test.dart
git commit -m "Show Splitwise-style activity list on Friend Detail with hide-settled toggle"
```

---

## Notes for the implementer

- After Task 1's `supabase db push`, the RPC is live on the shared dev project, so the running app on the device reflects it immediately after a hot restart.
- The `get_shared_expenses` RPC and its two migrations are now unused by the app but stay in the migration history (forward-only). Do not delete the migration files.
- If a subagent cannot reach the linked Supabase project (no CLI auth), Task 1 Steps 3–5 cannot run; surface that rather than marking them done.
