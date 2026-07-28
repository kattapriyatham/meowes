# Complete Core Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire up five gaps found in a screen-by-screen audit — friend requests, join-group-by-code, expense editing, and expense history on both Friend Detail and Group Detail — completing the app's core expense-splitting loop.

**Architecture:** Most of this reuses repository methods that already exist but were never called from any screen (`acceptFriendRequest`, `joinByInviteCode`, `confirmSettlement`, `watchPendingForMe`). Two small forward-only SQL migrations add what's genuinely missing: a `friendships` delete policy (for declining requests) and a `get_shared_expenses` RPC (for 1:1 expense history, which can't be expressed as a single-table filter the way group expense history can).

**Tech Stack:** Flutter (Material 3), `flutter_riverpod`, `supabase_flutter`, Supabase Postgres/RLS.

## Global Constraints

- `flutter test` must stay green throughout — the two pre-existing widget tests (`test/features/home/home_screen_test.dart`, `test/features/expenses/expense_detail_screen_test.dart`) and all repository tests.
- New repository methods that carry real logic (ordering, recompute, delete+reinsert) get a unit test, following this codebase's existing convention — thin pass-through wrappers (plain RPC calls, plain `.stream()`/`.select()` wrappers) do not, matching `watchFriendships`/`getPublicProfiles`/`markPaid`/etc., none of which have dedicated tests today.
- No new Flutter packages.
- Every new/changed screen keeps the app-wide `AppTheme.light` and reuses `lib/core/widgets/` components (`AppCard`, `AppAvatar`, `AppOutlinedButton`, `BalanceSummaryCard`, `EmptyStateBox`, `SectionHeader`) — no new ad-hoc styling.
- Both new migrations get pushed to the linked Supabase project (`supabase db push --linked --yes`) and manually verified against real data before being considered done, matching this session's established workflow for the `get_group_debts`/realtime-publication fixes.
- Reference spec: `docs/superpowers/specs/2026-07-28-complete-core-loop-design.md`.

---

### Task 1: Friendships delete policy + `declineFriendRequest`

**Files:**
- Create: `supabase/migrations/20260728120000_friendships_delete_policy.sql`
- Modify: `lib/repositories/friend_repository.dart`
- Test: `test/repositories/friend_repository_test.dart`

**Interfaces:**
- Produces: `FriendRepository.declineFriendRequest(String fromUserId) -> Future<void>` (used by Task 5).

- [ ] **Step 1: Write the migration**

```sql
-- friendships had no delete policy at all (only select/insert/update),
-- so there was no way to decline a pending request — the row would just
-- sit there forever. Either party to the friendship may delete it.
create policy friendships_delete_party on friendships
  for delete to authenticated using (
    auth.uid() = user_id_a or auth.uid() = user_id_b
  );
```

- [ ] **Step 2: Push the migration and verify**

Run: `supabase db push --linked --dry-run` (expect it to list this one migration), then `supabase db push --linked --yes`.

Verify manually via the Supabase REST API with the service_role key (same pattern used earlier this session): confirm a `DELETE` on a test `friendships` row now succeeds for either party and is blocked for a third user. If you don't have the project's URL/service_role key in this context, ask the user for them rather than guessing — do not skip this verification.

- [ ] **Step 3: Write the failing test**

Add to `test/repositories/friend_repository_test.dart` (the file already has `MockSupabaseClient`, `MockGoTrueClient`, `MockQueryBuilder`, and `dart:async`/mocktail/supabase_flutter imports — add this test function inside the existing `void main() { ... }` block, after the `sendFriendRequest` test):

```dart
class _FakeFilterChain extends Fake implements PostgrestFilterBuilder<PostgrestList> {
  final List<MapEntry<String, dynamic>> eqCalls = [];

  @override
  PostgrestFilterBuilder<PostgrestList> eq(String column, Object value) {
    eqCalls.add(MapEntry(column, value));
    return this;
  }

  @override
  Future<U> then<U>(FutureOr<U> Function(PostgrestList) onValue, {Function? onError}) {
    return Future.value(<Map<String, dynamic>>[]).then(onValue, onError: onError);
  }
}

// Add this as a second test() call inside the existing main() block:
test('declineFriendRequest deletes the friendship row with ordered user ids', () async {
  final client = MockSupabaseClient();
  final auth = MockGoTrueClient();
  final table = MockQueryBuilder();
  final deleteChain = _FakeFilterChain();

  when(() => client.auth).thenReturn(auth);
  when(() => auth.currentUser).thenReturn(
    User(
      id: 'bbbbbbbb-0000-0000-0000-000000000000',
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-07-27T00:00:00Z',
    ),
  );
  when(() => client.from('friendships')).thenAnswer((_) => table);
  when(() => table.delete()).thenAnswer((_) => deleteChain);

  final repo = FriendRepository(client);
  await repo.declineFriendRequest('aaaaaaaa-0000-0000-0000-000000000000');

  expect(deleteChain.eqCalls, [
    const MapEntry('user_id_a', 'aaaaaaaa-0000-0000-0000-000000000000'),
    const MapEntry('user_id_b', 'bbbbbbbb-0000-0000-0000-000000000000'),
  ]);
});
```

- [ ] **Step 4: Run test to verify it fails**

Run: `flutter test test/repositories/friend_repository_test.dart`
Expected: FAIL — `declineFriendRequest` is not defined on `FriendRepository`.

- [ ] **Step 5: Implement `declineFriendRequest`**

Add to `lib/repositories/friend_repository.dart`, after `acceptFriendRequest`:

```dart
  Future<void> declineFriendRequest(String fromUserId) async {
    final me = _client.auth.currentUser!.id;
    final userIdA = me.compareTo(fromUserId) < 0 ? me : fromUserId;
    final userIdB = me.compareTo(fromUserId) < 0 ? fromUserId : me;
    await _client
        .from('friendships')
        .delete()
        .eq('user_id_a', userIdA)
        .eq('user_id_b', userIdB);
  }
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/repositories/friend_repository_test.dart`
Expected: PASS (2/2).

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/20260728120000_friendships_delete_policy.sql lib/repositories/friend_repository.dart test/repositories/friend_repository_test.dart
git commit -m "Add friendships delete policy and FriendRepository.declineFriendRequest"
```

---

### Task 2: `get_shared_expenses` RPC + `getSharedExpenses`

**Files:**
- Create: `supabase/migrations/20260728120100_get_shared_expenses.sql`
- Modify: `lib/repositories/expense_repository.dart`

**Interfaces:**
- Consumes: `Expense.fromJson` (unchanged, from `lib/models/expense.dart`).
- Produces: `ExpenseRepository.getSharedExpenses(String otherUserId) -> Future<List<Expense>>` (used by Task 9).

- [ ] **Step 1: Write the migration**

```sql
-- Direct (non-group) expenses between exactly two people can't be
-- expressed as a single-table filter the way group expenses can (need
-- "no group AND both people involved"), so this is a small RPC, same
-- pattern as the existing get_friend_balance.
--
-- Must be security definer, not security invoker: when other_user is the
-- payer (not auth.uid()), the exists check against
-- expense_splits.user_id = other_user runs on a non-group expense the
-- caller neither paid nor created, which expense_splits_select_participant
-- RLS would normally hide from them — an invoker-security function would
-- silently under-return real shared expenses in exactly that case.
-- Bypassing RLS here is safe because the query's own two exists clauses
-- already constrain every returned row to one where BOTH auth.uid() and
-- other_user have a split — a caller can never get back an expense they
-- weren't actually part of.
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

- [ ] **Step 2: Push the migration and verify**

Run: `supabase db push --linked --dry-run`, then `supabase db push --linked --yes`.

Verify manually against the live linked project using two of the seeded test accounts from earlier this session (e.g. Alex/testuser1 and Sam) with a real 1:1 expense between them: call the RPC via the REST API (`POST /rest/v1/rpc/get_shared_expenses` with `{"other_user": "<sam-id>"}` and an Alex access token) and confirm it returns the expected row(s). If no direct (non-group) expense exists yet between two seeded users, create one first via the app or a direct insert, matching this session's earlier seeding pattern.

- [ ] **Step 3: Implement `getSharedExpenses`**

Add to `lib/repositories/expense_repository.dart`, after `deleteExpense` (no test — thin RPC wrapper, matching this file's existing untested `deleteExpense`/`editExpense` pattern before this plan's Task 4 changes):

```dart
  Future<List<Expense>> getSharedExpenses(String otherUserId) async {
    final rows = await _client.rpc('get_shared_expenses', params: {'other_user': otherUserId});
    final results = rows is List<dynamic> ? rows : const <dynamic>[];
    final expenses = results.map((r) => Expense.fromJson(r as Map<String, dynamic>)).toList();
    expenses.sort((a, b) => b.expenseDate.compareTo(a.expenseDate));
    return expenses;
  }
```

- [ ] **Step 4: Verify it compiles and existing tests still pass**

Run: `flutter analyze lib/repositories/expense_repository.dart`
Expected: `No issues found!`

Run: `flutter test test/repositories/expense_repository_test.dart`
Expected: PASS (existing `createExpense` test unaffected).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260728120100_get_shared_expenses.sql lib/repositories/expense_repository.dart
git commit -m "Add get_shared_expenses RPC and ExpenseRepository.getSharedExpenses"
```

---

### Task 3: `ExpenseRepository.watchExpenses` for Group Detail

**Files:**
- Modify: `lib/repositories/expense_repository.dart`

**Interfaces:**
- Produces: `ExpenseRepository.watchExpenses({required String groupId}) -> Stream<List<Expense>>` (used by Task 8).

- [ ] **Step 1: Implement `watchExpenses`**

Add to `lib/repositories/expense_repository.dart`, after `getSharedExpenses` (no test — thin `.stream()` wrapper, same convention as the existing untested `watchFriendships`/`watchMyGroups`):

```dart
  Stream<List<Expense>> watchExpenses({required String groupId}) {
    return _client
        .from('expenses')
        .stream(primaryKey: ['id'])
        .eq('group_id', groupId)
        .map((rows) {
      final expenses = rows.map(Expense.fromJson).where((e) => !e.isDeleted).toList();
      expenses.sort((a, b) => b.expenseDate.compareTo(a.expenseDate));
      return expenses;
    });
  }
```

- [ ] **Step 2: Verify it compiles and existing tests still pass**

Run: `flutter analyze lib/repositories/expense_repository.dart`
Expected: `No issues found!`

Run: `flutter test test/repositories/expense_repository_test.dart`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add lib/repositories/expense_repository.dart
git commit -m "Add ExpenseRepository.watchExpenses for group expense history"
```

---

### Task 4: Fix expense editing (re-split on edit) + `getExpenseSplits`

**Files:**
- Modify: `lib/repositories/expense_repository.dart` (full replacement)
- Test: `test/repositories/expense_repository_test.dart`

**Interfaces:**
- Consumes: `ExpenseSplit`/`ExpenseSplit.fromJson` (unchanged, from `lib/models/expense_split.dart`); `SplitCalculator.calculate` (unchanged, from `lib/splitting/split_calculator.dart`).
- Produces: `ExpenseRepository.editExpense` gains four new required/optional params (`splitType`, `participantIds`, `percentages`, `exactAmounts`) — used by Task 7. `ExpenseRepository.getExpenseSplits(String expenseId) -> Future<List<ExpenseSplit>>` — used by Task 7.

**Context:** `editExpense` currently only updates `description`/`amount` — it never touches `expense_splits`, despite a comment claiming otherwise. Nothing in the app calls it today. This task extends it to actually re-split, mirroring `createExpense`'s split-writing logic via a shared private helper.

- [ ] **Step 1: Write the failing test**

Add to `test/repositories/expense_repository_test.dart`, inside the existing `main()` block, after the `createExpense` test (reuses the file's existing `MockSupabaseClient`/`MockGoTrueClient`/`MockQueryBuilder`/`_FakeInsertResult` classes — add these two new Fakes above `void main()`, next to the existing ones):

```dart
class _FakeFilterChain extends Fake implements PostgrestFilterBuilder<PostgrestList> {
  @override
  PostgrestFilterBuilder<PostgrestList> eq(String column, Object value) => this;

  @override
  Future<U> then<U>(FutureOr<U> Function(PostgrestList) onValue, {Function? onError}) {
    return Future.value(<Map<String, dynamic>>[]).then(onValue, onError: onError);
  }
}

// Add this as a second test() call inside the existing main() block:
test('editExpense replaces old splits with a fresh SplitCalculator recompute', () async {
  final client = MockSupabaseClient();
  final auth = MockGoTrueClient();
  final expensesTable = MockQueryBuilder();
  final splitsTable = MockQueryBuilder();

  when(() => client.auth).thenReturn(auth);
  when(() => auth.currentUser).thenReturn(
    User(
      id: 'u1',
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-07-27T00:00:00Z',
    ),
  );
  when(() => client.from('expenses')).thenAnswer((_) => expensesTable);
  when(() => client.from('expense_splits')).thenAnswer((_) => splitsTable);
  when(() => expensesTable.update(any())).thenAnswer((_) => _FakeFilterChain());
  when(() => splitsTable.delete()).thenAnswer((_) => _FakeFilterChain());
  when(() => splitsTable.insert(any())).thenAnswer((_) => _FakeInsertResult());

  final repo = ExpenseRepository(client);
  await repo.editExpense(
    expenseId: 'e1',
    description: 'Coffee (updated)',
    amountMinorUnits: 10000,
    splitType: SplitType.equal,
    participantIds: ['u1', 'u2'],
  );

  final captured = verify(() => splitsTable.insert(captureAny())).captured.single
      as List<Map<String, dynamic>>;
  expect(captured, containsAll([
    {'expense_id': 'e1', 'user_id': 'u1', 'share_amount': '50.00'},
    {'expense_id': 'e1', 'user_id': 'u2', 'share_amount': '50.00'},
  ]));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/repositories/expense_repository_test.dart`
Expected: FAIL — `editExpense` doesn't accept `splitType`/`participantIds` params.

- [ ] **Step 3: Replace `lib/repositories/expense_repository.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/models/expense.dart';
import 'package:meowes_app/models/expense_split.dart';
import 'package:meowes_app/splitting/split_calculator.dart';

class ExpenseRepository {
  final SupabaseClient _client;
  ExpenseRepository(this._client);

  Future<Expense> createExpense({
    required String description,
    required int amountMinorUnits,
    String? groupId,
    required String paidBy,
    required SplitType splitType,
    required List<String> participantIds,
    Map<String, double>? percentages,
    Map<String, int>? exactAmounts,
    required DateTime expenseDate,
  }) async {
    final me = _client.auth.currentUser!.id;
    final row = await _client
        .from('expenses')
        .insert({
          'group_id': groupId,
          'paid_by': paidBy,
          'description': description,
          'amount': (amountMinorUnits / 100).toStringAsFixed(2),
          'currency': 'INR',
          'expense_date': expenseDate.toIso8601String().split('T').first,
          'created_by': me,
        })
        .select()
        .single();
    final expense = Expense.fromJson(row);

    await _writeSplits(
      expenseId: expense.id,
      amountMinorUnits: amountMinorUnits,
      splitType: splitType,
      participantIds: participantIds,
      percentages: percentages,
      exactAmounts: exactAmounts,
    );

    return expense;
  }

  Future<void> editExpense({
    required String expenseId,
    required String description,
    required int amountMinorUnits,
    required SplitType splitType,
    required List<String> participantIds,
    Map<String, double>? percentages,
    Map<String, int>? exactAmounts,
  }) async {
    final me = _client.auth.currentUser!.id;
    await _client.from('expenses').update({
      'description': description,
      'amount': (amountMinorUnits / 100).toStringAsFixed(2),
      'edited_at': DateTime.now().toIso8601String(),
      'edited_by': me,
    }).eq('id', expenseId);

    await _client.from('expense_splits').delete().eq('expense_id', expenseId);

    await _writeSplits(
      expenseId: expenseId,
      amountMinorUnits: amountMinorUnits,
      splitType: splitType,
      participantIds: participantIds,
      percentages: percentages,
      exactAmounts: exactAmounts,
    );
  }

  Future<void> deleteExpense(String expenseId) async {
    await _client
        .from('expenses')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', expenseId);
  }

  Future<List<ExpenseSplit>> getExpenseSplits(String expenseId) async {
    final rows = await _client.from('expense_splits').select().eq('expense_id', expenseId);
    return rows.map(ExpenseSplit.fromJson).toList();
  }

  Future<List<Expense>> getSharedExpenses(String otherUserId) async {
    final rows = await _client.rpc('get_shared_expenses', params: {'other_user': otherUserId});
    final results = rows is List<dynamic> ? rows : const <dynamic>[];
    final expenses = results.map((r) => Expense.fromJson(r as Map<String, dynamic>)).toList();
    expenses.sort((a, b) => b.expenseDate.compareTo(a.expenseDate));
    return expenses;
  }

  Stream<List<Expense>> watchExpenses({required String groupId}) {
    return _client
        .from('expenses')
        .stream(primaryKey: ['id'])
        .eq('group_id', groupId)
        .map((rows) {
      final expenses = rows.map(Expense.fromJson).where((e) => !e.isDeleted).toList();
      expenses.sort((a, b) => b.expenseDate.compareTo(a.expenseDate));
      return expenses;
    });
  }

  Future<void> _writeSplits({
    required String expenseId,
    required int amountMinorUnits,
    required SplitType splitType,
    required List<String> participantIds,
    Map<String, double>? percentages,
    Map<String, int>? exactAmounts,
  }) async {
    final shares = SplitCalculator.calculate(
      totalMinorUnits: amountMinorUnits,
      type: splitType,
      participantIds: participantIds,
      percentages: percentages,
      exactAmounts: exactAmounts,
    );

    await _client.from('expense_splits').insert([
      for (final entry in shares.entries)
        {
          'expense_id': expenseId,
          'user_id': entry.key,
          'share_amount': (entry.value / 100).toStringAsFixed(2),
        },
    ]);
  }
}

final expenseRepositoryProvider = Provider<ExpenseRepository>(
  (ref) => ExpenseRepository(ref.watch(supabaseClientProvider)),
);
```

(This replacement folds in Task 2's `getSharedExpenses` and Task 3's `watchExpenses` — if those tasks already landed on this branch, this step is just adding `getExpenseSplits`, extending `editExpense`'s signature, and extracting `_writeSplits`. Diff carefully against what's already there rather than blindly overwriting.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/repositories/expense_repository_test.dart`
Expected: PASS (2/2).

- [ ] **Step 5: Run full suite and analyze**

Run: `flutter analyze lib/repositories/expense_repository.dart`
Expected: `No issues found!`

Run: `flutter test`
Expected: all passing (no other file references `editExpense` yet, so nothing else breaks).

- [ ] **Step 6: Commit**

```bash
git add lib/repositories/expense_repository.dart test/repositories/expense_repository_test.dart
git commit -m "Fix expense editing to actually re-split; add getExpenseSplits"
```

---

### Task 5: Notifications screen (friend requests + settlement confirmations)

**Files:**
- Create: `lib/features/notifications/notifications_screen.dart`
- Modify: `lib/features/home/home_screen.dart`

**Interfaces:**
- Consumes: `FriendRepository.watchFriendships()`, `.acceptFriendRequest(String)`, `.declineFriendRequest(String)` (Task 1), `.getPublicProfiles(List<String>)` (all from `lib/repositories/friend_repository.dart`); `SettlementRepository.watchPendingForMe()`, `.confirmSettlement(String)` (from `lib/repositories/settlement_repository.dart`, provider `settlementRepositoryProvider` declared in `lib/features/settlements/settle_up_screen.dart`); `AppCard`, `AppAvatar`, `EmptyStateBox`, `SectionHeader` (from `lib/core/widgets/widgets.dart`).

- [ ] **Step 1: Create `lib/features/notifications/notifications_screen.dart`**

```dart
// lib/features/notifications/notifications_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart' show friendRepositoryProvider;
import 'package:meowes_app/features/settlements/settle_up_screen.dart' show settlementRepositoryProvider;
import 'package:meowes_app/models/app_user.dart';
import 'package:meowes_app/models/friendship.dart';
import 'package:meowes_app/models/settlement.dart';
import 'package:meowes_app/repositories/friend_repository.dart';
import 'package:meowes_app/repositories/settlement_repository.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    final friendRepo = ref.watch(friendRepositoryProvider);
    final settlementRepo = ref.watch(settlementRepositoryProvider);
    final me = client.auth.currentUser!.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: StreamBuilder<List<Friendship>>(
        stream: friendRepo.watchFriendships(),
        builder: (context, friendshipSnapshot) {
          final pendingRequesterIds = (friendshipSnapshot.data ?? [])
              .where((f) => f.status == FriendshipStatus.pending && f.requestedBy != me)
              .map((f) => f.userIdA == me ? f.userIdB : f.userIdA)
              .toList();

          return StreamBuilder<List<Settlement>>(
            stream: settlementRepo.watchPendingForMe(),
            builder: (context, settlementSnapshot) {
              final settlements = settlementSnapshot.data ?? [];

              if (pendingRequesterIds.isEmpty && settlements.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: EmptyStateBox(
                    icon: Icons.notifications_none,
                    message: 'Nothing needs your attention right now.',
                  ),
                );
              }

              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (pendingRequesterIds.isNotEmpty) ...[
                    const SectionHeader(title: 'Friend requests'),
                    const SizedBox(height: 12),
                    _PendingRequestsList(friendRepo: friendRepo, requesterIds: pendingRequesterIds),
                    const SizedBox(height: 24),
                  ],
                  if (settlements.isNotEmpty) ...[
                    const SectionHeader(title: 'Settlements to confirm'),
                    const SizedBox(height: 12),
                    _PendingSettlementsList(
                      friendRepo: friendRepo,
                      settlementRepo: settlementRepo,
                      settlements: settlements,
                    ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _PendingRequestsList extends StatelessWidget {
  final FriendRepository friendRepo;
  final List<String> requesterIds;
  const _PendingRequestsList({required this.friendRepo, required this.requesterIds});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AppUser>>(
      future: friendRepo.getPublicProfiles(requesterIds),
      builder: (context, snapshot) {
        final names = {for (final p in snapshot.data ?? <AppUser>[]) p.id: p.name};
        return Column(
          children: [
            for (final id in requesterIds) ...[
              AppCard(
                child: Row(
                  children: [
                    AppAvatar(seed: id, label: names[id] ?? '...'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(names[id] ?? '...', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    TextButton(
                      onPressed: () => friendRepo.declineFriendRequest(id),
                      child: const Text('Decline', style: TextStyle(color: AppColors.owingText)),
                    ),
                    ElevatedButton(
                      onPressed: () => friendRepo.acceptFriendRequest(id),
                      child: const Text('Accept'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

class _PendingSettlementsList extends StatelessWidget {
  final FriendRepository friendRepo;
  final SettlementRepository settlementRepo;
  final List<Settlement> settlements;
  const _PendingSettlementsList({
    required this.friendRepo,
    required this.settlementRepo,
    required this.settlements,
  });

  @override
  Widget build(BuildContext context) {
    final fromUserIds = settlements.map((s) => s.fromUser).toSet().toList();
    return FutureBuilder<List<AppUser>>(
      future: friendRepo.getPublicProfiles(fromUserIds),
      builder: (context, snapshot) {
        final names = {for (final p in snapshot.data ?? <AppUser>[]) p.id: p.name};
        return Column(
          children: [
            for (final s in settlements) ...[
              AppCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${names[s.fromUser] ?? '...'} paid you',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '₹${(s.amountMinorUnits / 100).toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.owedText),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () => settlementRepo.confirmSettlement(s.id),
                      child: const Text('Confirm'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}
```

- [ ] **Step 2: Wire Home's bell icon to open it**

In `lib/features/home/home_screen.dart`, add the import (alongside the other `features/` imports):

```dart
import 'package:meowes_app/features/notifications/notifications_screen.dart';
```

Then replace the bell `Container` inside `_GreetingHeader.build` (currently a bare `Container` with no tap handler) with:

```dart
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              ),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: const Icon(Icons.notifications_none, color: AppColors.textDark),
              ),
            ),
```

- [ ] **Step 3: Verify it compiles and existing tests still pass**

Run: `flutter analyze lib/features/notifications/notifications_screen.dart lib/features/home/home_screen.dart`
Expected: `No issues found!`

Run: `flutter test test/features/home/home_screen_test.dart`
Expected: PASS — the test never taps the bell, so wrapping it in a `GestureDetector` doesn't change anything it asserts on.

Run: `flutter test`
Expected: all passing.

- [ ] **Step 4: Commit**

```bash
git add lib/features/notifications/notifications_screen.dart lib/features/home/home_screen.dart
git commit -m "Add Notifications screen for friend requests and settlement confirmations"
```

---

### Task 6: Join Group by Code

**Files:**
- Modify: `lib/features/groups/create_group_screen.dart` (full replacement)

**Interfaces:**
- Consumes: `GroupRepository.createGroup(String)`, `.joinByInviteCode(String)` (both unchanged, from `lib/repositories/group_repository.dart` — `joinByInviteCode` throws `StateError('Invalid invite code')` on failure, already covered by `test/repositories/group_repository_test.dart`).
- Produces: no change to `CreateGroupScreen`'s own public API (still `const CreateGroupScreen()`) or to `groupRepositoryProvider`'s declaration site.

- [ ] **Step 1: Replace `lib/features/groups/create_group_screen.dart`**

```dart
// lib/features/groups/create_group_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/models/group.dart';
import 'package:meowes_app/repositories/group_repository.dart';

final groupRepositoryProvider = Provider<GroupRepository>(
  (ref) => GroupRepository(ref.watch(supabaseClientProvider)),
);

class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  bool _isJoinMode = false;
  Group? _created;

  Future<void> _handleCreate(GroupRepository repo) async {
    final group = await repo.createGroup(_nameController.text.trim());
    if (!mounted) return;
    setState(() => _created = group);
  }

  Future<void> _handleJoin(GroupRepository repo) async {
    try {
      final group = await repo.joinByInviteCode(_codeController.text.trim());
      if (!mounted) return;
      setState(() => _created = group);
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(groupRepositoryProvider);

    if (_created != null) {
      final group = _created!;
      return Scaffold(
        appBar: AppBar(title: const Text('Group created')),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(group.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),
              const SectionHeader(title: 'Invite code'),
              const SizedBox(height: 12),
              AppCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        group.inviteCode,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 1.2),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, color: AppColors.coral),
                      onPressed: () => Clipboard.setData(ClipboardData(text: group.inviteCode)),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(group),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Create group')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _ModeTab(
                    label: 'Create',
                    selected: !_isJoinMode,
                    onTap: () => setState(() => _isJoinMode = false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ModeTab(
                    label: 'Join',
                    selected: _isJoinMode,
                    onTap: () => setState(() => _isJoinMode = true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_isJoinMode) ...[
              TextField(
                controller: _codeController,
                decoration: const InputDecoration(labelText: 'Invite code'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _handleJoin(repo),
                  child: const Text('Join'),
                ),
              ),
            ] else ...[
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Group name'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _handleCreate(repo),
                  child: const Text('Create'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModeTab({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.coral : Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textDark,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles and existing tests still pass**

Run: `flutter analyze lib/features/groups/create_group_screen.dart`
Expected: `No issues found!`

Run: `flutter test`
Expected: all passing.

- [ ] **Step 3: Commit**

```bash
git add lib/features/groups/create_group_screen.dart
git commit -m "Add Create/Join toggle to Create Group screen"
```

---

### Task 7: Wire expense editing end-to-end + show participant shares on Expense Detail

**Files:**
- Modify: `lib/features/expenses/add_expense_screen.dart` (full replacement)
- Modify: `lib/features/expenses/expense_detail_screen.dart` (full replacement)
- Test: `test/features/expenses/expense_detail_screen_test.dart`

**Interfaces:**
- Consumes: `ExpenseRepository.editExpense` (extended signature, Task 4), `.getExpenseSplits` (Task 4); `ExpenseSplit` (from `lib/models/expense_split.dart`); `friendRepositoryProvider`/`FriendRepository.getPublicProfiles` (unchanged).
- Produces: `AddExpenseScreen` gains two new optional constructor params: `Expense? editing`, `List<ExpenseSplit>? existingSplits`. Existing callers (Friend Detail's Add Expense button, both already-completed) are unaffected since both new params default to `null`.

**Context:** `ExpenseDetailScreen`'s Edit button currently passes `participantIds: const []` (a stub). This task makes it pass the real participants and their splits (via `getExpenseSplits`, Task 4), and makes `AddExpenseScreen` actually prefill and call `editExpense` instead of always calling `createExpense`. It also adds the "participant shares" list to `ExpenseDetailScreen` that the original restyle spec called for but the implementation never added — free, since this task already fetches the splits it needs for editing.

- [ ] **Step 1: Replace `lib/features/expenses/add_expense_screen.dart`**

```dart
// lib/features/expenses/add_expense_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart' show friendRepositoryProvider;
import 'package:meowes_app/models/app_user.dart';
import 'package:meowes_app/models/expense.dart';
import 'package:meowes_app/models/expense_split.dart';
import 'package:meowes_app/repositories/expense_repository.dart';
import 'package:meowes_app/splitting/split_calculator.dart';

class AddExpenseScreen extends ConsumerStatefulWidget {
  final String? groupId;
  final List<String> participantIds;
  final Expense? editing;
  final List<ExpenseSplit>? existingSplits;

  const AddExpenseScreen({
    super.key,
    this.groupId,
    required this.participantIds,
    this.editing,
    this.existingSplits,
  });

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  SplitType _splitType = SplitType.equal;
  late String _paidBy;
  final Map<String, TextEditingController> _percentControllers = {};
  final Map<String, double> _exactAmounts = {};
  late final Future<List<AppUser>> _profilesFuture;
  String _me = '';

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    final existingSplits = widget.existingSplits;

    _paidBy = widget.participantIds.isEmpty
        ? ''
        : (editing?.paidBy ?? widget.participantIds.first);
    final evenPercent = widget.participantIds.isEmpty
        ? '0'
        : (100 / widget.participantIds.length).toStringAsFixed(1);
    for (final id in widget.participantIds) {
      _percentControllers[id] = TextEditingController(text: evenPercent);
      _exactAmounts[id] = 0;
    }

    if (editing != null && existingSplits != null && existingSplits.isNotEmpty) {
      _descriptionController.text = editing.description;
      _amountController.text = (editing.amountMinorUnits / 100).toStringAsFixed(2);
      _splitType = SplitType.exact;
      for (final split in existingSplits) {
        _exactAmounts[split.userId] = split.shareAmountMinorUnits / 100;
        final pct = editing.amountMinorUnits == 0
            ? 0.0
            : split.shareAmountMinorUnits / editing.amountMinorUnits * 100;
        _percentControllers[split.userId]?.text = pct.toStringAsFixed(1);
      }
    }

    // Attached after any prefill above so setting .text programmatically
    // doesn't trigger _onAmountChanged and reset the just-restored exact
    // amounts back to an even split.
    _amountController.addListener(_onAmountChanged);

    _profilesFuture = widget.participantIds.isEmpty
        ? Future.value(<AppUser>[])
        : ref.read(friendRepositoryProvider).getPublicProfiles(widget.participantIds);
  }

  void _onAmountChanged() {
    final total = double.tryParse(_amountController.text) ?? 0;
    final even = widget.participantIds.isEmpty ? 0.0 : total / widget.participantIds.length;
    setState(() {
      for (final id in widget.participantIds) {
        _exactAmounts[id] = even;
      }
    });
  }

  @override
  void dispose() {
    _amountController.removeListener(_onAmountChanged);
    _descriptionController.dispose();
    _amountController.dispose();
    for (final c in _percentControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  double get _totalAmount => double.tryParse(_amountController.text) ?? 0;

  double get _percentTotal => widget.participantIds.fold<double>(
        0,
        (sum, id) => sum + (double.tryParse(_percentControllers[id]!.text) ?? 0),
      );

  double get _exactTotal =>
      widget.participantIds.fold<double>(0, (sum, id) => sum + (_exactAmounts[id] ?? 0));

  bool get _canSave {
    if (_descriptionController.text.trim().isEmpty || _totalAmount <= 0) return false;
    if (_splitType == SplitType.percentage) {
      if (widget.participantIds.any((id) => double.tryParse(_percentControllers[id]!.text) == null)) {
        return false;
      }
      return (_percentTotal - 100).abs() < 0.01;
    }
    if (_splitType == SplitType.exact) {
      return (_exactTotal - _totalAmount).abs() < 0.01 && _computeExactSharesInPaise() != null;
    }
    return true;
  }

  Map<String, int>? _computeExactSharesInPaise() {
    final ids = widget.participantIds;
    final amountMinorUnits = (_totalAmount * 100).round();
    final result = <String, int>{};
    var allocated = 0;
    for (var i = 0; i < ids.length; i++) {
      if (i == ids.length - 1) {
        result[ids[i]] = amountMinorUnits - allocated;
      } else {
        final share = (_exactAmounts[ids[i]]! * 100).round();
        result[ids[i]] = share;
        allocated += share;
      }
    }
    if (result.values.any((v) => v < 0)) return null;
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(expenseRepositoryProvider);
    _me = ref.watch(supabaseClientProvider).auth.currentUser!.id;
    final isEditing = widget.editing != null;

    if (widget.participantIds.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(isEditing ? 'Edit expense' : 'Add expense')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No participants to split this expense with yet.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Edit expense' : 'Add expense')),
      body: FutureBuilder<List<AppUser>>(
        future: _profilesFuture,
        builder: (context, snapshot) {
          final names = {for (final p in snapshot.data ?? <AppUser>[]) p.id: p.name};
          String nameOf(String id) => id == _me ? 'Me' : (names[id] ?? '...');

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _amountController,
                decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 20),
              const SectionHeader(title: 'Paid by'),
              const SizedBox(height: 8),
              for (final id in widget.participantIds)
                RadioListTile<String>(
                  value: id,
                  groupValue: _paidBy,
                  onChanged: (v) => setState(() => _paidBy = v!),
                  title: Text(nameOf(id)),
                  activeColor: AppColors.coral,
                  contentPadding: EdgeInsets.zero,
                ),
              const SizedBox(height: 12),
              const SectionHeader(title: 'Split between'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final id in widget.participantIds)
                    Chip(
                      avatar: AppAvatar(seed: id, label: nameOf(id), size: 24),
                      label: Text(nameOf(id)),
                      backgroundColor: Colors.white,
                    ),
                ],
              ),
              const SizedBox(height: 20),
              const SectionHeader(title: 'Split type'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _SplitTypeTile(
                      label: 'Equal',
                      icon: Icons.balance,
                      color: AppColors.avatarPalette[4],
                      selected: _splitType == SplitType.equal,
                      onTap: () => setState(() => _splitType = SplitType.equal),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SplitTypeTile(
                      label: 'Percentage',
                      icon: Icons.percent,
                      color: AppColors.avatarPalette[1],
                      selected: _splitType == SplitType.percentage,
                      onTap: () => setState(() => _splitType = SplitType.percentage),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SplitTypeTile(
                      label: 'Exact',
                      icon: Icons.tune,
                      color: AppColors.avatarPalette[3],
                      selected: _splitType == SplitType.exact,
                      onTap: () => setState(() => _splitType = SplitType.exact),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (_splitType == SplitType.percentage) ...[
                for (final id in widget.participantIds)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Expanded(child: Text(nameOf(id))),
                        SizedBox(
                          width: 90,
                          child: TextField(
                            controller: _percentControllers[id],
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(suffixText: '%'),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                  ),
                Text(
                  'Total: ${_percentTotal.toStringAsFixed(1)}% (needs to be 100%)',
                  style: TextStyle(
                    color: (_percentTotal - 100).abs() < 0.01 ? AppColors.owedText : AppColors.owingText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (_splitType == SplitType.exact) ...[
                for (final id in widget.participantIds)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(nameOf(id))),
                            Text('₹${(_exactAmounts[id] ?? 0).toStringAsFixed(2)}'),
                          ],
                        ),
                        Slider(
                          value: (_exactAmounts[id] ?? 0).clamp(0, _totalAmount == 0 ? 1 : _totalAmount),
                          min: 0,
                          max: _totalAmount == 0 ? 1 : _totalAmount,
                          activeColor: AppColors.coral,
                          onChanged: _totalAmount == 0
                              ? null
                              : (v) => setState(() => _exactAmounts[id] = v),
                        ),
                      ],
                    ),
                  ),
                Text(
                  'Remaining: ₹${(_totalAmount - _exactTotal).toStringAsFixed(2)}',
                  style: TextStyle(
                    color: (_totalAmount - _exactTotal).abs() < 0.01 ? AppColors.owedText : AppColors.owingText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _canSave
                      ? () async {
                          final amountMinorUnits = (_totalAmount * 100).round();
                          final percentages = _splitType == SplitType.percentage
                              ? {
                                  for (final id in widget.participantIds)
                                    id: double.parse(_percentControllers[id]!.text),
                                }
                              : null;
                          final exactAmounts =
                              _splitType == SplitType.exact ? _computeExactSharesInPaise() : null;

                          if (isEditing) {
                            await repo.editExpense(
                              expenseId: widget.editing!.id,
                              description: _descriptionController.text.trim(),
                              amountMinorUnits: amountMinorUnits,
                              splitType: _splitType,
                              participantIds: widget.participantIds,
                              percentages: percentages,
                              exactAmounts: exactAmounts,
                            );
                          } else {
                            await repo.createExpense(
                              description: _descriptionController.text.trim(),
                              amountMinorUnits: amountMinorUnits,
                              groupId: widget.groupId,
                              paidBy: _paidBy,
                              splitType: _splitType,
                              participantIds: widget.participantIds,
                              percentages: percentages,
                              exactAmounts: exactAmounts,
                              expenseDate: DateTime.now(),
                            );
                          }
                          if (context.mounted) Navigator.of(context).pop();
                        }
                      : null,
                  child: Text(isEditing ? 'Save Changes' : 'Save Expense'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SplitTypeTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _SplitTypeTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? color : Colors.transparent, width: 2),
        ),
        child: Column(
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Replace `lib/features/expenses/expense_detail_screen.dart`**

```dart
// lib/features/expenses/expense_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart' show friendRepositoryProvider;
import 'package:meowes_app/models/app_user.dart';
import 'package:meowes_app/models/expense.dart';
import 'package:meowes_app/models/expense_split.dart';
import 'package:meowes_app/repositories/expense_repository.dart';
import 'package:meowes_app/features/expenses/add_expense_screen.dart';

class _ExpenseDetailData {
  final List<ExpenseSplit> splits;
  final Map<String, String> namesById;
  const _ExpenseDetailData({required this.splits, required this.namesById});
}

class ExpenseDetailScreen extends ConsumerWidget {
  final Expense expense;
  const ExpenseDetailScreen({super.key, required this.expense});

  Future<_ExpenseDetailData> _load(WidgetRef ref) async {
    final repo = ref.read(expenseRepositoryProvider);
    final friendRepo = ref.read(friendRepositoryProvider);
    final splits = await repo.getExpenseSplits(expense.id);
    final participantIds = splits.map((s) => s.userId).toList();
    final profiles =
        participantIds.isEmpty ? <AppUser>[] : await friendRepo.getPublicProfiles(participantIds);
    final namesById = {for (final p in profiles) p.id: p.name};
    return _ExpenseDetailData(splits: splits, namesById: namesById);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(expenseRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(expense.description)),
      body: FutureBuilder<_ExpenseDetailData>(
        future: _load(ref),
        builder: (context, snapshot) {
          final data = snapshot.data ?? const _ExpenseDetailData(splits: [], namesById: {});
          String nameOf(String id) => data.namesById[id] ?? 'Unknown';

          return Padding(
            padding: const EdgeInsets.all(20),
            child: ListView(
              children: [
                Text(
                  '₹${(expense.amountMinorUnits / 100).toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                if (expense.isEdited)
                  const Text('Edited', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                const SizedBox(height: 24),
                const SectionHeader(title: 'Split between'),
                const SizedBox(height: 12),
                for (final s in data.splits) ...[
                  AppCard(
                    child: Row(
                      children: [
                        AppAvatar(seed: s.userId, label: nameOf(s.userId)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(nameOf(s.userId), style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        Text(
                          '₹${(s.shareAmountMinorUnits / 100).toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: AppOutlinedButton(
                        label: 'Edit',
                        color: AppColors.coral,
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AddExpenseScreen(
                              groupId: expense.groupId,
                              participantIds: data.splits.map((s) => s.userId).toList(),
                              editing: expense,
                              existingSplits: data.splits,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppOutlinedButton(
                        label: 'Delete',
                        color: AppColors.owingText,
                        onPressed: () async {
                          await repo.deleteExpense(expense.id);
                          if (context.mounted) Navigator.of(context).pop();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 3: Update `test/features/expenses/expense_detail_screen_test.dart`**

The existing tests construct `ExpenseDetailScreen` with only `expenseRepositoryProvider` overridden. The new `_load` also reads `friendRepositoryProvider` (via `ref.read`), and unconditionally calls `getExpenseSplits` — both need mocking or the test will try to hit the real `Supabase.instance.client` chain / throw on an unstubbed Mock call. Replace the full file:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:meowes_app/features/expenses/expense_detail_screen.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart';
import 'package:meowes_app/models/expense.dart';
import 'package:meowes_app/repositories/expense_repository.dart';
import 'package:meowes_app/repositories/friend_repository.dart';

class MockExpenseRepository extends Mock implements ExpenseRepository {}
class MockFriendRepository extends Mock implements FriendRepository {}

void main() {
  testWidgets('ExpenseDetailScreen shows Edit and Delete actions for a participant', (tester) async {
    final expense = Expense(
      id: 'e1',
      groupId: null,
      paidBy: 'u1',
      description: 'Coffee',
      amountMinorUnits: 10000,
      currency: 'INR',
      expenseDate: DateTime(2026, 7, 27),
      createdAt: DateTime(2026, 7, 27),
      createdBy: 'u1',
    );

    final mockExpenseRepo = MockExpenseRepository();
    final mockFriendRepo = MockFriendRepository();
    when(() => mockExpenseRepo.getExpenseSplits(any())).thenAnswer((_) async => []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expenseRepositoryProvider.overrideWithValue(mockExpenseRepo),
          friendRepositoryProvider.overrideWithValue(mockFriendRepo),
        ],
        child: MaterialApp(home: ExpenseDetailScreen(expense: expense)),
      ),
    );
    await tester.pump();

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Coffee'), findsOneWidget);
  });

  testWidgets('ExpenseDetailScreen shows an edited indicator when editedAt is set', (tester) async {
    final expense = Expense(
      id: 'e1',
      groupId: null,
      paidBy: 'u1',
      description: 'Coffee',
      amountMinorUnits: 10000,
      currency: 'INR',
      expenseDate: DateTime(2026, 7, 27),
      createdAt: DateTime(2026, 7, 27),
      createdBy: 'u1',
      editedAt: DateTime(2026, 7, 28),
      editedBy: 'u2',
    );

    final mockExpenseRepo = MockExpenseRepository();
    final mockFriendRepo = MockFriendRepository();
    when(() => mockExpenseRepo.getExpenseSplits(any())).thenAnswer((_) async => []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expenseRepositoryProvider.overrideWithValue(mockExpenseRepo),
          friendRepositoryProvider.overrideWithValue(mockFriendRepo),
        ],
        child: MaterialApp(home: ExpenseDetailScreen(expense: expense)),
      ),
    );
    await tester.pump();

    expect(find.text('Edited'), findsOneWidget);
  });
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/expenses/expense_detail_screen_test.dart`
Expected: PASS (2/2).

- [ ] **Step 5: Analyze and run full suite**

Run: `flutter analyze lib/features/expenses/`
Expected: `No issues found!`

Run: `flutter test`
Expected: all passing.

- [ ] **Step 6: Commit**

```bash
git add lib/features/expenses/add_expense_screen.dart lib/features/expenses/expense_detail_screen.dart test/features/expenses/expense_detail_screen_test.dart
git commit -m "Wire expense editing end-to-end; show participant shares on Expense Detail"
```

---

### Task 8: Group Detail expense history

**Files:**
- Modify: `lib/features/groups/group_detail_screen.dart` (full replacement)

**Interfaces:**
- Consumes: `ExpenseRepository.watchExpenses({required String groupId})` (Task 3, via `expenseRepositoryProvider` from `lib/repositories/expense_repository.dart`); `ExpenseDetailScreen({required Expense expense})` (Task 7, unchanged constructor).

- [ ] **Step 1: Replace `lib/features/groups/group_detail_screen.dart`**

```dart
// lib/features/groups/group_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/expenses/expense_detail_screen.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart' show friendRepositoryProvider;
import 'package:meowes_app/features/settlements/settle_up_screen.dart';
import 'package:meowes_app/models/app_user.dart';
import 'package:meowes_app/models/expense.dart';
import 'package:meowes_app/repositories/expense_repository.dart';

class _GroupDetailData {
  final List<String> memberIds;
  final Map<String, String> namesById;
  final List<dynamic> debts;
  const _GroupDetailData({required this.memberIds, required this.namesById, required this.debts});
}

class GroupDetailScreen extends ConsumerWidget {
  final String groupId;
  const GroupDetailScreen({super.key, required this.groupId});

  Future<_GroupDetailData> _load(WidgetRef ref) async {
    final client = ref.read(supabaseClientProvider);
    final friendRepo = ref.read(friendRepositoryProvider);

    final memberRows = await client.from('group_members').select('user_id').eq('group_id', groupId);
    final memberIds = memberRows.map((r) => r['user_id'] as String).toList();

    final debtsRaw = await client.rpc('get_group_debts', params: {'target_group_id': groupId});
    final debts = (debtsRaw as List<dynamic>?) ?? [];

    final profiles = memberIds.isEmpty ? <AppUser>[] : await friendRepo.getPublicProfiles(memberIds);
    final namesById = {for (final p in profiles) p.id: p.name};

    return _GroupDetailData(memberIds: memberIds, namesById: namesById, debts: debts);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(supabaseClientProvider).auth.currentUser!.id;
    final expenseRepo = ref.watch(expenseRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Group')),
      body: FutureBuilder<_GroupDetailData>(
        future: _load(ref),
        builder: (context, snapshot) {
          final data = snapshot.data ?? const _GroupDetailData(memberIds: [], namesById: {}, debts: []);
          String nameOf(String id) => data.namesById[id] ?? 'Unknown';

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              AvatarStack(
                seeds: data.memberIds,
                labels: [for (final id in data.memberIds) nameOf(id)],
              ),
              const SizedBox(height: 20),
              const SectionHeader(title: 'Expenses'),
              const SizedBox(height: 12),
              StreamBuilder<List<Expense>>(
                stream: expenseRepo.watchExpenses(groupId: groupId),
                builder: (context, expenseSnapshot) {
                  final expenses = expenseSnapshot.data ?? [];
                  if (expenses.isEmpty) {
                    return const EmptyStateBox(
                      icon: Icons.receipt_long_outlined,
                      message: 'No expenses logged in this group yet.',
                    );
                  }
                  return Column(
                    children: [
                      for (final e in expenses) ...[
                        AppCard(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => ExpenseDetailScreen(expense: e)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  e.description,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                ),
                              ),
                              Text(
                                '₹${(e.amountMinorUnits / 100).toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              const SectionHeader(title: 'Smart settle suggestions'),
              const SizedBox(height: 12),
              if (data.debts.isEmpty)
                const EmptyStateBox(
                  icon: Icons.celebration_outlined,
                  message: 'Everyone is settled up.',
                )
              else
                Column(
                  children: [
                    for (final d in data.debts) ...[
                      AppCard(
                        // markPaid always records from_user = me, so only the
                        // actual debtor's own row should be tappable into
                        // settle-up — otherwise a member could record a
                        // settlement in their own name for someone else's debt.
                        onTap: d['from_user'] == me
                            ? () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => SettleUpScreen(
                                      toUser: d['to_user'] as String,
                                      amountMinorUnits:
                                          (double.parse(d['amount'].toString()) * 100).round(),
                                      groupId: groupId,
                                    ),
                                  ),
                                )
                            : null,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${nameOf(d['from_user'] as String)} owes ${nameOf(d['to_user'] as String)}',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                            ),
                            Text(
                              '₹${double.parse(d['amount'].toString()).toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.owingText),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles and existing tests still pass**

Run: `flutter analyze lib/features/groups/group_detail_screen.dart`
Expected: `No issues found!`

Run: `flutter test`
Expected: all passing.

- [ ] **Step 3: Commit**

```bash
git add lib/features/groups/group_detail_screen.dart
git commit -m "Add expense history to Group Detail"
```

---

### Task 9: Friend Detail expense history

**Files:**
- Modify: `lib/features/friends/friend_detail_screen.dart` (full replacement)

**Interfaces:**
- Consumes: `ExpenseRepository.getSharedExpenses(String)` (Task 2, via `expenseRepositoryProvider`); `ExpenseDetailScreen({required Expense expense})` (Task 7, unchanged constructor).

- [ ] **Step 1: Replace `lib/features/friends/friend_detail_screen.dart`**

```dart
// lib/features/friends/friend_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/core/widgets/widgets.dart';
import 'package:meowes_app/features/expenses/add_expense_screen.dart';
import 'package:meowes_app/features/expenses/expense_detail_screen.dart';
import 'package:meowes_app/features/settlements/settle_up_screen.dart';
import 'package:meowes_app/models/expense.dart';
import 'package:meowes_app/repositories/expense_repository.dart';

class FriendDetailScreen extends ConsumerWidget {
  final String friendUserId;
  const FriendDetailScreen({super.key, required this.friendUserId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    final expenseRepo = ref.watch(expenseRepositoryProvider);
    final me = client.auth.currentUser!.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Friend')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: FutureBuilder(
          future: client.rpc('get_friend_balance', params: {
            'user_a': me,
            'user_b': friendUserId,
          }),
          builder: (context, snapshot) {
            final balance = (snapshot.data as num?)?.toDouble() ?? 0;
            // get_friend_balance(me, friend) is positive when the friend owes
            // me, negative when I owe the friend. Settling here means "I paid
            // this" (markPaid always records from_user = me), so the button
            // only makes sense when I'm the one who owes — offering it when
            // the friend owes me would record a payment in the wrong direction.
            final iOwe = balance < -0.005;
            return ListView(
              children: [
                BalanceSummaryCard(balance: balance),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AddExpenseScreen(
                              participantIds: [me, friendUserId],
                            ),
                          ),
                        ),
                        child: const Text('Add Expense'),
                      ),
                    ),
                    if (iOwe) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppOutlinedButton(
                          label: 'Settle Up',
                          color: AppColors.coral,
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SettleUpScreen(
                                toUser: friendUserId,
                                amountMinorUnits: (balance.abs() * 100).round(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 24),
                const SectionHeader(title: 'Expense history'),
                const SizedBox(height: 12),
                FutureBuilder<List<Expense>>(
                  future: expenseRepo.getSharedExpenses(friendUserId),
                  builder: (context, expenseSnapshot) {
                    final expenses = expenseSnapshot.data ?? [];
                    if (expenses.isEmpty) {
                      return const EmptyStateBox(
                        icon: Icons.receipt_long_outlined,
                        message: 'No expenses with this friend yet.',
                      );
                    }
                    return Column(
                      children: [
                        for (final e in expenses) ...[
                          AppCard(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => ExpenseDetailScreen(expense: e)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    e.description,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                ),
                                Text(
                                  '₹${(e.amountMinorUnits / 100).toStringAsFixed(2)}',
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles and existing tests still pass**

Run: `flutter analyze lib/features/friends/friend_detail_screen.dart`
Expected: `No issues found!`

Run: `flutter test`
Expected: all passing.

- [ ] **Step 3: Commit**

```bash
git add lib/features/friends/friend_detail_screen.dart
git commit -m "Add expense history to Friend Detail"
```

---

### Task 10: Final verification

**Files:** none (verification only).

**Interfaces:** none.

- [ ] **Step 1: Full analyzer pass**

Run: `flutter analyze`
Expected: only the pre-existing known notices (flutter_lints include-not-found, `anonKey` deprecation, `setMockMethodCallHandler` deprecation, `unused_element_parameter`, the 2 `RadioListTile` deprecation notices) — no new issues.

- [ ] **Step 2: Full test suite**

Run: `flutter test`
Expected: `All tests passed!` — 21 pre-existing + 2 new (`declineFriendRequest`, `editExpense` re-split) = 23 tests.

- [ ] **Step 3: Emulator spot-check — Decline/Accept a friend request**

On the Android emulator (signed in as the seeded `testuser1`/"Alex" account), have a second seeded account (e.g. via the Supabase REST API, matching this session's earlier seeding pattern) send Alex a new friend request. Tap Home's bell icon → confirm it opens Notifications and shows the request under "Friend requests" with the requester's real name. Tap Decline on one, confirm it disappears (and a fresh REST query confirms the `friendships` row is gone). Send another, tap Accept, confirm it disappears from Notifications and the new friend now shows up on Home's Friends list.

- [ ] **Step 4: Emulator spot-check — Join a group by code**

From Home's `+` menu, open Create Group, switch to "Join," enter the invite code of one of the seeded groups (e.g. "Goa Trip"), confirm it joins successfully and the group's own invite-code screen is shown. Confirm the group now appears on Home for whichever test account performed the join.

- [ ] **Step 5: Emulator spot-check — Expense history + editing**

Open a seeded group with expenses (e.g. "Flatmates"). Confirm the new "Expenses" section lists the seeded expenses (e.g. "Wifi bill", "Groceries") with correct amounts, above "Smart settle suggestions." Tap one to open Expense Detail — confirm it now shows a "Split between" list with real participant names and amounts (not blank). Tap Edit, confirm the form is prefilled with the existing description/amount/exact-split amounts, change the amount, save, and confirm the change reflects both on Expense Detail and in the group's Smart Settle numbers (i.e. the re-split actually took effect).

- [ ] **Step 6: Emulator spot-check — Settlement confirmation**

Mark a settlement as paid from one account (Settle Up flow, already existing), then sign in as (or otherwise check, via REST) the recipient account and confirm the settlement now shows under Notifications → "Settlements to confirm." Tap Confirm, and confirm it disappears from Notifications and the relevant balance updates accordingly.

- [ ] **Step 7: Commit any fixes found during spot-check**

If steps 3–6 surface a bug, fix it, re-run `flutter analyze` and `flutter test`, then commit with a message describing the specific fix (not a generic "fix bug").
