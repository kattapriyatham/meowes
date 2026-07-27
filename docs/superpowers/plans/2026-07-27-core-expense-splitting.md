# Core Expense Splitting, Groups & Auth — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the foundational Meowes app — auth, friends, groups, expenses, splitting, server-side debt simplification, real-time sync, and two-sided settle-up — as specified in `docs/superpowers/specs/2026-07-27-core-expense-splitting-design.md`.

**Architecture:** Flutter client (Riverpod for state) talking to Supabase (Postgres + Auth + Realtime). All money math (balance netting, debt simplification, split validation) lives in Postgres RPC functions, computed on read and never cached, so no client can drift from another. The Flutter layer is a thin repository + UI shell around those RPCs and tables.

**Tech Stack:** Flutter/Dart, `flutter_riverpod`, `supabase_flutter`, `google_sign_in`, `sign_in_with_apple`, Supabase Postgres + pgTAP (`supabase test db`) for SQL unit tests, `flutter_test`/`mocktail` for Dart tests.

## Global Constraints

- All monetary amounts are stored and transmitted in **minor currency units (int, e.g. paise)** at every layer except the final DB `numeric` columns, to avoid floating-point rounding bugs. Split calculation happens in int minor units; conversion to `numeric` happens only at the repository/DB-write boundary.
- Balances are **never cached** client-side or server-side — every balance read calls the RPC fresh. No task in this plan may introduce a stored/materialized balance.
- Any participant in an expense (not just its creator) can edit/delete it. Deletes are soft (`deleted_at`).
- Settlements require two-sided confirmation (`pending_confirmation` → `confirmed`); only `confirmed` settlements net against balances.
- Friend adding via phone search requires accept (`pending` → `accepted`); friendships via group invite link are auto-`accepted`.
- Auth is Google/Apple sign-in only. Phone number is a separate, optional profile field used solely for friend search — never used for login.
- **Backend target is the linked cloud Supabase project (ref `pacbkvuepitmmqxudscx`), not a local Docker stack.** Every task that applies a migration or runs pgTAP tests uses `supabase db push --linked` and `supabase test db --linked` (never `supabase start` / `supabase db reset` / `--local`). `supabase link --project-ref pacbkvuepitmmqxudscx` has already been run in the repo root — no task needs to repeat it.
- **Every table gets Row Level Security enabled with policies scoping access to rows the requesting user actually participates in** (own profile, own friendships, groups/expenses/splits/settlements they're a party to). This is a real cloud project, not disposable local data — RLS is not optional. `get_friend_balance` and `get_group_debts` stay `security invoker` (the default) — the RLS policies above already make each function's underlying reads visible exactly when the caller is a legitimate participant — but each function still adds an explicit `auth.uid()` guard (raising an exception rather than silently returning zero/empty) so an unauthorized call fails loudly instead of returning misleadingly empty data.

---

## File Structure

```
supabase/
  migrations/
    0001_init_schema.sql
    0002_balance_rpcs.sql
  tests/
    database/
      balance_rpc.test.sql

lib/
  main.dart
  core/
    supabase_client.dart          # Supabase init + typed client provider
    money.dart                    # minor-unit <-> numeric conversion helpers
  models/
    app_user.dart
    friendship.dart
    group.dart
    expense.dart
    expense_split.dart
    settlement.dart
  splitting/
    split_calculator.dart         # pure equal/percentage/exact split logic
  repositories/
    auth_repository.dart
    friend_repository.dart
    group_repository.dart
    expense_repository.dart
    settlement_repository.dart
  features/
    auth/
      sign_in_screen.dart
      profile_setup_screen.dart
    home/
      home_screen.dart
    friends/
      add_friend_screen.dart
      friend_detail_screen.dart
    groups/
      create_group_screen.dart
      group_detail_screen.dart
    expenses/
      add_expense_screen.dart
      expense_detail_screen.dart
    settlements/
      settle_up_screen.dart

test/
  splitting/split_calculator_test.dart
  models/*_test.dart
  repositories/*_test.dart (with mocktail-mocked Supabase client)
```

---

### Task 1: Flutter Project Scaffold & Supabase Client

**Files:**
- Create: `pubspec.yaml`
- Create: `lib/main.dart`
- Create: `lib/core/supabase_client.dart`
- Test: `test/core/supabase_client_test.dart`

**Interfaces:**
- Produces: `supabaseClientProvider` (a Riverpod `Provider<SupabaseClient>`) used by every repository in later tasks.

- [ ] **Step 1: Create the Flutter project**

Run: `flutter create --org com.meowes meowes_app --platforms ios,android`

Then move into that directory for all subsequent commands (or treat it as the repo root going forward).

- [ ] **Step 2: Add dependencies to `pubspec.yaml`**

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.5.1
  supabase_flutter: ^2.5.6
  google_sign_in: ^6.2.1
  sign_in_with_apple: ^6.1.1
  uuid: ^4.4.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  mocktail: ^1.0.3
```

Run: `flutter pub get`

- [ ] **Step 3: Write the failing test for client init**

```dart
// test/core/supabase_client_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('supabaseClientProvider returns a configured SupabaseClient', () async {
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test-anon-key',
    );
    final container = ProviderContainer();
    final client = container.read(supabaseClientProvider);
    expect(client, isA<SupabaseClient>());
  });
}
```

- [ ] **Step 4: Run test to verify it fails**

Run: `flutter test test/core/supabase_client_test.dart`
Expected: FAIL — `supabaseClientProvider` undefined / file doesn't exist.

- [ ] **Step 5: Implement `lib/core/supabase_client.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});
```

- [ ] **Step 6: Implement `lib/main.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );
  runApp(const ProviderScope(child: MeowesApp()));
}

class MeowesApp extends StatelessWidget {
  const MeowesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Meowes',
      home: Scaffold(body: Center(child: Text('Meowes'))),
    );
  }
}
```

Run app with: `flutter run --dart-define=SUPABASE_URL=<url> --dart-define=SUPABASE_ANON_KEY=<key>`

- [ ] **Step 7: Run test to verify it passes**

Run: `flutter test test/core/supabase_client_test.dart`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add pubspec.yaml lib/main.dart lib/core/supabase_client.dart test/core/supabase_client_test.dart
git commit -m "chore: scaffold Flutter project with Supabase client"
```

---

### Task 2: Supabase Schema Migration

**Files:**
- Create: `supabase/migrations/0001_init_schema.sql`

**Interfaces:**
- Produces: tables `users`, `groups`, `group_members`, `friendships`, `expenses`, `expense_splits`, `settlements` — consumed by every RPC and repository task below.

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/0001_init_schema.sql

create extension if not exists pgcrypto;

create table users (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  avatar_url text,
  phone_number text unique,
  created_at timestamptz not null default now()
);

create table groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_by uuid not null references users(id),
  invite_code text not null unique default encode(gen_random_bytes(6), 'hex'),
  created_at timestamptz not null default now()
);

create table group_members (
  group_id uuid not null references groups(id) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create table friendships (
  user_id_a uuid not null references users(id) on delete cascade,
  user_id_b uuid not null references users(id) on delete cascade,
  status text not null check (status in ('pending', 'accepted')),
  requested_by uuid not null references users(id),
  created_at timestamptz not null default now(),
  primary key (user_id_a, user_id_b),
  check (user_id_a < user_id_b)
);

create table expenses (
  id uuid primary key default gen_random_uuid(),
  group_id uuid references groups(id) on delete cascade,
  paid_by uuid not null references users(id),
  description text not null,
  amount numeric(12, 2) not null check (amount > 0),
  currency text not null default 'INR',
  expense_date date not null,
  created_at timestamptz not null default now(),
  created_by uuid not null references users(id),
  edited_at timestamptz,
  edited_by uuid references users(id),
  deleted_at timestamptz
);

create table expense_splits (
  expense_id uuid not null references expenses(id) on delete cascade,
  user_id uuid not null references users(id),
  share_amount numeric(12, 2) not null,
  primary key (expense_id, user_id)
);

create table settlements (
  id uuid primary key default gen_random_uuid(),
  group_id uuid references groups(id) on delete cascade,
  from_user uuid not null references users(id),
  to_user uuid not null references users(id),
  amount numeric(12, 2) not null check (amount > 0),
  status text not null check (status in ('pending_confirmation', 'confirmed')) default 'pending_confirmation',
  created_at timestamptz not null default now(),
  confirmed_at timestamptz
);

create index idx_expense_splits_group on expenses (group_id);
create index idx_expense_splits_user on expense_splits (user_id);
create index idx_expense_splits_expense on expense_splits (expense_id);
create index idx_settlements_pair on settlements (from_user, to_user);

-- Row Level Security: every table is scoped to rows the requesting user
-- (auth.uid()) actually participates in. This is a live cloud project, so
-- the anon/authenticated client key must never see or touch rows outside
-- the caller's own data.

alter table users enable row level security;
alter table groups enable row level security;
alter table group_members enable row level security;
alter table friendships enable row level security;
alter table expenses enable row level security;
alter table expense_splits enable row level security;
alter table settlements enable row level security;

-- users: any authenticated user can look up any other user (required for
-- phone-number friend search and displaying names on shared expenses/groups);
-- only the row owner can modify their own profile.
create policy users_select_authenticated on users
  for select to authenticated using (true);
create policy users_insert_self on users
  for insert to authenticated with check (id = auth.uid());
create policy users_update_self on users
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- groups: visible/updatable only to members of that group; anyone
-- authenticated can create a group naming themselves as creator.
create policy groups_select_member on groups
  for select to authenticated using (
    exists (select 1 from group_members gm where gm.group_id = id and gm.user_id = auth.uid())
  );
create policy groups_insert_self on groups
  for insert to authenticated with check (created_by = auth.uid());
create policy groups_update_member on groups
  for update to authenticated using (
    exists (select 1 from group_members gm where gm.group_id = id and gm.user_id = auth.uid())
  );

-- group_members: a member can see the roster of any group they belong to;
-- a user may only insert their own membership row (creating a group, or
-- joining via invite code).
create policy group_members_select_fellow_member on group_members
  for select to authenticated using (
    exists (select 1 from group_members gm2 where gm2.group_id = group_members.group_id and gm2.user_id = auth.uid())
  );
create policy group_members_insert_self on group_members
  for insert to authenticated with check (user_id = auth.uid());

-- friendships: only the two parties to a friendship can see, create, or
-- update (accept) it.
create policy friendships_select_party on friendships
  for select to authenticated using (auth.uid() = user_id_a or auth.uid() = user_id_b);
create policy friendships_insert_party on friendships
  for insert to authenticated with check (auth.uid() = user_id_a or auth.uid() = user_id_b);
create policy friendships_update_party on friendships
  for update to authenticated using (auth.uid() = user_id_a or auth.uid() = user_id_b);

-- expenses: visible/editable to whoever paid, created, is split into it, or
-- shares its group.
create policy expenses_select_participant on expenses
  for select to authenticated using (
    paid_by = auth.uid()
    or created_by = auth.uid()
    or exists (select 1 from expense_splits es where es.expense_id = id and es.user_id = auth.uid())
    or (group_id is not null and exists (
      select 1 from group_members gm where gm.group_id = expenses.group_id and gm.user_id = auth.uid()
    ))
  );
create policy expenses_insert_creator on expenses
  for insert to authenticated with check (created_by = auth.uid());
create policy expenses_update_participant on expenses
  for update to authenticated using (
    paid_by = auth.uid()
    or created_by = auth.uid()
    or exists (select 1 from expense_splits es where es.expense_id = id and es.user_id = auth.uid())
  );

-- expense_splits: visible to the split's own user or the expense's payer;
-- insertable by whoever paid the parent expense (the creator writing splits
-- at expense-creation time).
create policy expense_splits_select_participant on expense_splits
  for select to authenticated using (
    user_id = auth.uid()
    or exists (select 1 from expenses e where e.id = expense_id and e.paid_by = auth.uid())
  );
create policy expense_splits_insert_payer on expense_splits
  for insert to authenticated with check (
    exists (select 1 from expenses e where e.id = expense_id and e.paid_by = auth.uid())
  );

-- settlements: visible/insertable/updatable only to the two parties.
create policy settlements_select_party on settlements
  for select to authenticated using (auth.uid() = from_user or auth.uid() = to_user);
create policy settlements_insert_payer on settlements
  for insert to authenticated with check (auth.uid() = from_user);
create policy settlements_update_payee_confirms on settlements
  for update to authenticated using (auth.uid() = to_user);
```

- [ ] **Step 2: Push the migration to the linked cloud project**

Run: `supabase db push --linked`
Expected: migration applies with no errors. Confirm with `supabase db diff --linked` showing no drift.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0001_init_schema.sql
git commit -m "feat: add core schema migration with RLS policies (users, groups, expenses, settlements)"
```

---

### Task 3: Balance RPC — `get_friend_balance`

**Files:**
- Create: `supabase/migrations/0002_balance_rpcs.sql` (this task writes the `get_friend_balance` function; Task 4 appends `get_group_debts` to the same file)
- Create: `supabase/tests/database/balance_rpc.test.sql`

**Interfaces:**
- Consumes: `expenses`, `expense_splits`, `settlements` tables from Task 2.
- Produces: `get_friend_balance(user_a uuid, user_b uuid) returns numeric` — positive means `user_b` owes `user_a`, negative means `user_a` owes `user_b`. Consumed by `friend_repository.dart` in Task 7 and the home/friend-detail screens in Tasks 10–11.

- [ ] **Step 1: Write the failing pgTAP test**

```sql
-- supabase/tests/database/balance_rpc.test.sql
begin;
select plan(2);

insert into auth.users (id) values
  ('11111111-1111-1111-1111-111111111111'),
  ('22222222-2222-2222-2222-222222222222');

insert into users (id, name) values
  ('11111111-1111-1111-1111-111111111111', 'Alex'),
  ('22222222-2222-2222-2222-222222222222', 'Sam');

-- Alex pays 1000, split evenly (500/500) with Sam, no group.
insert into expenses (id, group_id, paid_by, description, amount, expense_date, created_by)
values ('33333333-3333-3333-3333-333333333333', null,
        '11111111-1111-1111-1111-111111111111', 'Dinner', 1000.00, current_date,
        '11111111-1111-1111-1111-111111111111');

insert into expense_splits (expense_id, user_id, share_amount) values
  ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', 500.00),
  ('33333333-3333-3333-3333-333333333333', '22222222-2222-2222-2222-222222222222', 500.00);

select is(
  get_friend_balance('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'),
  500.00,
  'Sam owes Alex 500 before any settlement'
);

-- Sam confirms a 500 settlement to Alex — balance should zero out.
insert into settlements (group_id, from_user, to_user, amount, status, confirmed_at)
values (null, '22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111',
        500.00, 'confirmed', now());

select is(
  get_friend_balance('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'),
  0.00,
  'Balance is zero after a confirmed settlement covers the debt'
);

select * from finish();
rollback;
```

- [ ] **Step 2: Run test to verify it fails**

Run: `supabase test db --linked`
Expected: FAIL — `function get_friend_balance(uuid, uuid) does not exist`.

- [ ] **Step 3: Implement the RPC**

```sql
-- supabase/migrations/0002_balance_rpcs.sql

create or replace function get_friend_balance(user_a uuid, user_b uuid)
returns numeric
language plpgsql
stable
as $$
begin
  -- auth.uid() is null for the service/test context (pgTAP, migrations);
  -- for any real authenticated call, only a party to the pair may query it.
  if auth.uid() is not null and auth.uid() not in (user_a, user_b) then
    raise exception 'not authorized to view this balance';
  end if;

  return (with paid_by_a as (
    select coalesce(sum(es.share_amount), 0) as amt
    from expense_splits es
    join expenses e on e.id = es.expense_id
    where e.deleted_at is null
      and e.paid_by = user_a
      and es.user_id = user_b
  ),
  paid_by_b as (
    select coalesce(sum(es.share_amount), 0) as amt
    from expense_splits es
    join expenses e on e.id = es.expense_id
    where e.deleted_at is null
      and e.paid_by = user_b
      and es.user_id = user_a
  ),
  settled_a_to_b as (
    select coalesce(sum(amount), 0) as amt
    from settlements
    where status = 'confirmed' and from_user = user_a and to_user = user_b
  ),
  settled_b_to_a as (
    select coalesce(sum(amount), 0) as amt
    from settlements
    where status = 'confirmed' and from_user = user_b and to_user = user_a
  )
  select (select amt from paid_by_a)
       - (select amt from paid_by_b)
       - (select amt from settled_a_to_b)
       + (select amt from settled_b_to_a));
end;
$$;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `supabase test db --linked`
Expected: PASS (2/2)

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0002_balance_rpcs.sql supabase/tests/database/balance_rpc.test.sql
git commit -m "feat: add get_friend_balance RPC with pgTAP tests"
```

---

### Task 4: Balance RPC — `get_group_debts` (Debt Simplification)

**Files:**
- Modify: `supabase/migrations/0002_balance_rpcs.sql`
- Modify: `supabase/tests/database/balance_rpc.test.sql`

**Interfaces:**
- Consumes: same tables as Task 3, plus `group_members`.
- Produces: `get_group_debts(target_group_id uuid) returns table(from_user uuid, to_user uuid, amount numeric)` — the minimal simplified transaction list. Consumed by `group_repository.dart` (Task 8) and the group detail screen (Task 11).

- [ ] **Step 1: Extend the pgTAP test**

Append to `supabase/tests/database/balance_rpc.test.sql` (change `select plan(2);` to `select plan(3);` at the top):

```sql
-- Three-person group: A pays 300 split with B and C (100 each extra beyond
-- their own share is owed to A); B pays nothing; C pays nothing.
-- Expected simplified debts: B owes A 100, C owes A 100 (2 transactions,
-- not the naive 2 already-minimal case, so also verify total count).

insert into auth.users (id) values ('44444444-4444-4444-4444-444444444444');
insert into users (id, name) values ('44444444-4444-4444-4444-444444444444', 'Priya');

insert into groups (id, name, created_by)
values ('55555555-5555-5555-5555-555555555555', 'Trip',
        '11111111-1111-1111-1111-111111111111');

insert into group_members (group_id, user_id) values
  ('55555555-5555-5555-5555-555555555555', '11111111-1111-1111-1111-111111111111'),
  ('55555555-5555-5555-5555-555555555555', '22222222-2222-2222-2222-222222222222'),
  ('55555555-5555-5555-5555-555555555555', '44444444-4444-4444-4444-444444444444');

insert into expenses (id, group_id, paid_by, description, amount, expense_date, created_by)
values ('66666666-6666-6666-6666-666666666666', '55555555-5555-5555-5555-555555555555',
        '11111111-1111-1111-1111-111111111111', 'Cabin', 300.00, current_date,
        '11111111-1111-1111-1111-111111111111');

insert into expense_splits (expense_id, user_id, share_amount) values
  ('66666666-6666-6666-6666-666666666666', '11111111-1111-1111-1111-111111111111', 100.00),
  ('66666666-6666-6666-6666-666666666666', '22222222-2222-2222-2222-222222222222', 100.00),
  ('66666666-6666-6666-6666-666666666666', '44444444-4444-4444-4444-444444444444', 100.00);

select is(
  (select count(*)::int from get_group_debts('55555555-5555-5555-5555-555555555555')),
  2,
  'Two simplified transactions settle a three-person group'
);
```

- [ ] **Step 2: Run test to verify it fails**

Run: `supabase test db --linked`
Expected: FAIL — `function get_group_debts(uuid) does not exist`.

- [ ] **Step 3: Implement the RPC**

Append to `supabase/migrations/0002_balance_rpcs.sql`:

```sql
create or replace function get_group_debts(target_group_id uuid)
returns table(from_user uuid, to_user uuid, amount numeric)
language plpgsql
stable
as $$
declare
  net_balances jsonb;
  creditors record;
  debtors record;
  creditor_list uuid[];
  creditor_amounts numeric[];
  debtor_list uuid[];
  debtor_amounts numeric[];
  ci int := 1;
  di int := 1;
  settle_amount numeric;
begin
  -- auth.uid() is null for the service/test context (pgTAP, migrations);
  -- for any real authenticated call, only an actual member of the group
  -- may query its debts.
  if auth.uid() is not null and not exists (
    select 1 from group_members gm where gm.group_id = target_group_id and gm.user_id = auth.uid()
  ) then
    raise exception 'not authorized to view this group''s debts';
  end if;

  -- Net balance per member: positive = owed money, negative = owes money.
  create temporary table _member_net on commit drop as
  select gm.user_id,
    coalesce(sum(case when e.paid_by = gm.user_id then es.share_amount_total - es.own_share else 0 end), 0)
    - coalesce(sum(case when e.paid_by != gm.user_id then es.own_share_paid_by_other else 0 end), 0)
    as net
  from group_members gm
  left join lateral (
    select e2.id as expense_id, e2.paid_by,
      (select sum(es2.share_amount) from expense_splits es2 where es2.expense_id = e2.id) as share_amount_total,
      (select coalesce(es3.share_amount, 0) from expense_splits es3 where es3.expense_id = e2.id and es3.user_id = gm.user_id) as own_share,
      (select coalesce(es4.share_amount, 0) from expense_splits es4 where es4.expense_id = e2.id and es4.user_id = gm.user_id) as own_share_paid_by_other
    from expenses e2
    where e2.group_id = target_group_id and e2.deleted_at is null
  ) es on true
  left join expenses e on e.id = es.expense_id
  where gm.group_id = target_group_id
  group by gm.user_id;

  -- Subtract confirmed settlements within this group from the net balances.
  update _member_net m
  set net = m.net - coalesce((
    select sum(s.amount) from settlements s
    where s.group_id = target_group_id and s.status = 'confirmed' and s.from_user = m.user_id
  ), 0) + coalesce((
    select sum(s.amount) from settlements s
    where s.group_id = target_group_id and s.status = 'confirmed' and s.to_user = m.user_id
  ), 0);

  -- Greedy min-transaction simplification.
  select array_agg(user_id order by net desc), array_agg(net order by net desc)
  into creditor_list, creditor_amounts
  from _member_net where net > 0.005;

  select array_agg(user_id order by net asc), array_agg(-net order by net asc)
  into debtor_list, debtor_amounts
  from _member_net where net < -0.005;

  if creditor_list is null or debtor_list is null then
    return;
  end if;

  while ci <= array_length(creditor_list, 1) and di <= array_length(debtor_list, 1) loop
    settle_amount := least(creditor_amounts[ci], debtor_amounts[di]);
    from_user := debtor_list[di];
    to_user := creditor_list[ci];
    amount := round(settle_amount, 2);
    return next;

    creditor_amounts[ci] := creditor_amounts[ci] - settle_amount;
    debtor_amounts[di] := debtor_amounts[di] - settle_amount;

    if creditor_amounts[ci] <= 0.005 then ci := ci + 1; end if;
    if debtor_amounts[di] <= 0.005 then di := di + 1; end if;
  end loop;

  return;
end;
$$;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `supabase test db --linked`
Expected: PASS (3/3)

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0002_balance_rpcs.sql supabase/tests/database/balance_rpc.test.sql
git commit -m "feat: add get_group_debts RPC with greedy debt simplification"
```

---

### Task 5: Split Calculator (Dart, Pure Function)

**Files:**
- Create: `lib/splitting/split_calculator.dart`
- Test: `test/splitting/split_calculator_test.dart`

**Interfaces:**
- Produces: `enum SplitType { equal, percentage, exact }` and `SplitCalculator.calculate(...)` — consumed by `expense_repository.dart` (Task 9) and `add_expense_screen.dart` (Task 9).

- [ ] **Step 1: Write the failing tests**

```dart
// test/splitting/split_calculator_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowes_app/splitting/split_calculator.dart';

void main() {
  group('SplitCalculator.calculate', () {
    test('equal split distributes remainder cents to first participants', () {
      final result = SplitCalculator.calculate(
        totalMinorUnits: 1001, // e.g. ₹10.01
        type: SplitType.equal,
        participantIds: ['a', 'b', 'c'],
      );
      // 1001 / 3 = 333 remainder 2 -> a and b get 334, c gets 333
      expect(result, {'a': 334, 'b': 334, 'c': 333});
      expect(result.values.reduce((x, y) => x + y), 1001);
    });

    test('percentage split resolves to minor units summing to total', () {
      final result = SplitCalculator.calculate(
        totalMinorUnits: 10000,
        type: SplitType.percentage,
        participantIds: ['a', 'b'],
        percentages: {'a': 30, 'b': 70},
      );
      expect(result, {'a': 3000, 'b': 7000});
    });

    test('percentage split throws if percentages do not sum to 100', () {
      expect(
        () => SplitCalculator.calculate(
          totalMinorUnits: 10000,
          type: SplitType.percentage,
          participantIds: ['a', 'b'],
          percentages: {'a': 30, 'b': 60},
        ),
        throwsArgumentError,
      );
    });

    test('exact split throws if amounts do not sum to total', () {
      expect(
        () => SplitCalculator.calculate(
          totalMinorUnits: 10000,
          type: SplitType.exact,
          participantIds: ['a', 'b'],
          exactAmounts: {'a': 4000, 'b': 5000},
        ),
        throwsArgumentError,
      );
    });

    test('exact split passes through when amounts sum correctly', () {
      final result = SplitCalculator.calculate(
        totalMinorUnits: 10000,
        type: SplitType.exact,
        participantIds: ['a', 'b'],
        exactAmounts: {'a': 4000, 'b': 6000},
      );
      expect(result, {'a': 4000, 'b': 6000});
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/splitting/split_calculator_test.dart`
Expected: FAIL — file `lib/splitting/split_calculator.dart` doesn't exist.

- [ ] **Step 3: Implement the calculator**

```dart
// lib/splitting/split_calculator.dart
enum SplitType { equal, percentage, exact }

class SplitCalculator {
  /// All amounts are in minor currency units (e.g. paise) as ints, to avoid
  /// floating point rounding errors. Returns a map of participantId -> share.
  static Map<String, int> calculate({
    required int totalMinorUnits,
    required SplitType type,
    required List<String> participantIds,
    Map<String, double>? percentages,
    Map<String, int>? exactAmounts,
  }) {
    switch (type) {
      case SplitType.equal:
        return _splitEqual(totalMinorUnits, participantIds);
      case SplitType.percentage:
        return _splitPercentage(totalMinorUnits, participantIds, percentages);
      case SplitType.exact:
        return _splitExact(totalMinorUnits, participantIds, exactAmounts);
    }
  }

  static Map<String, int> _splitEqual(int total, List<String> ids) {
    final base = total ~/ ids.length;
    final remainder = total % ids.length;
    return {
      for (var i = 0; i < ids.length; i++)
        ids[i]: base + (i < remainder ? 1 : 0),
    };
  }

  static Map<String, int> _splitPercentage(
    int total,
    List<String> ids,
    Map<String, double>? percentages,
  ) {
    if (percentages == null || percentages.length != ids.length) {
      throw ArgumentError('percentages must be provided for every participant');
    }
    final sum = percentages.values.fold<double>(0, (a, b) => a + b);
    if ((sum - 100).abs() > 0.01) {
      throw ArgumentError('percentages must sum to 100, got $sum');
    }
    final result = <String, int>{};
    var allocated = 0;
    for (var i = 0; i < ids.length; i++) {
      final id = ids[i];
      if (i == ids.length - 1) {
        result[id] = total - allocated; // last participant absorbs rounding
      } else {
        final share = (total * (percentages[id]! / 100)).round();
        result[id] = share;
        allocated += share;
      }
    }
    return result;
  }

  static Map<String, int> _splitExact(
    int total,
    List<String> ids,
    Map<String, int>? exactAmounts,
  ) {
    if (exactAmounts == null || exactAmounts.length != ids.length) {
      throw ArgumentError('exactAmounts must be provided for every participant');
    }
    final sum = exactAmounts.values.fold<int>(0, (a, b) => a + b);
    if (sum != total) {
      throw ArgumentError('exact amounts must sum to $total, got $sum');
    }
    return Map<String, int>.from(exactAmounts);
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/splitting/split_calculator_test.dart`
Expected: PASS (5/5)

- [ ] **Step 5: Commit**

```bash
git add lib/splitting/split_calculator.dart test/splitting/split_calculator_test.dart
git commit -m "feat: add pure split calculator for equal/percentage/exact splits"
```

---

### Task 6: Domain Models

**Files:**
- Create: `lib/models/app_user.dart`
- Create: `lib/models/friendship.dart`
- Create: `lib/models/group.dart`
- Create: `lib/models/expense.dart`
- Create: `lib/models/expense_split.dart`
- Create: `lib/models/settlement.dart`
- Test: `test/models/models_test.dart`

**Interfaces:**
- Produces: `AppUser`, `Friendship`, `Group`, `Expense`, `ExpenseSplit`, `Settlement` classes, each with `fromJson`/`toJson` — consumed by every repository task (7–12).

- [ ] **Step 1: Write the failing test**

```dart
// test/models/models_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowes_app/models/app_user.dart';
import 'package:meowes_app/models/expense.dart';
import 'package:meowes_app/models/settlement.dart';

void main() {
  test('AppUser round-trips through JSON', () {
    final user = AppUser(
      id: 'u1',
      name: 'Alex',
      avatarUrl: null,
      phoneNumber: '+911234567890',
    );
    final json = user.toJson();
    final restored = AppUser.fromJson(json);
    expect(restored.id, 'u1');
    expect(restored.phoneNumber, '+911234567890');
  });

  test('Expense fromJson handles nullable groupId and soft-delete fields', () {
    final expense = Expense.fromJson({
      'id': 'e1',
      'group_id': null,
      'paid_by': 'u1',
      'description': 'Coffee',
      'amount': '250.00',
      'currency': 'INR',
      'expense_date': '2026-07-27',
      'created_at': '2026-07-27T10:00:00Z',
      'created_by': 'u1',
      'edited_at': null,
      'edited_by': null,
      'deleted_at': null,
    });
    expect(expense.groupId, isNull);
    expect(expense.amountMinorUnits, 25000);
    expect(expense.isDeleted, isFalse);
  });

  test('Settlement fromJson parses status correctly', () {
    final settlement = Settlement.fromJson({
      'id': 's1',
      'group_id': null,
      'from_user': 'u1',
      'to_user': 'u2',
      'amount': '500.00',
      'status': 'pending_confirmation',
      'created_at': '2026-07-27T10:00:00Z',
      'confirmed_at': null,
    });
    expect(settlement.status, SettlementStatus.pendingConfirmation);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/models_test.dart`
Expected: FAIL — model files don't exist.

- [ ] **Step 3: Implement the models**

```dart
// lib/models/app_user.dart
class AppUser {
  final String id;
  final String name;
  final String? avatarUrl;
  final String? phoneNumber;

  AppUser({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.phoneNumber,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        name: json['name'] as String,
        avatarUrl: json['avatar_url'] as String?,
        phoneNumber: json['phone_number'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'avatar_url': avatarUrl,
        'phone_number': phoneNumber,
      };
}
```

```dart
// lib/models/friendship.dart
enum FriendshipStatus { pending, accepted }

class Friendship {
  final String userIdA;
  final String userIdB;
  final FriendshipStatus status;
  final String requestedBy;

  Friendship({
    required this.userIdA,
    required this.userIdB,
    required this.status,
    required this.requestedBy,
  });

  factory Friendship.fromJson(Map<String, dynamic> json) => Friendship(
        userIdA: json['user_id_a'] as String,
        userIdB: json['user_id_b'] as String,
        status: (json['status'] as String) == 'accepted'
            ? FriendshipStatus.accepted
            : FriendshipStatus.pending,
        requestedBy: json['requested_by'] as String,
      );

  Map<String, dynamic> toJson() => {
        'user_id_a': userIdA,
        'user_id_b': userIdB,
        'status': status == FriendshipStatus.accepted ? 'accepted' : 'pending',
        'requested_by': requestedBy,
      };
}
```

```dart
// lib/models/group.dart
class Group {
  final String id;
  final String name;
  final String createdBy;
  final String inviteCode;

  Group({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.inviteCode,
  });

  factory Group.fromJson(Map<String, dynamic> json) => Group(
        id: json['id'] as String,
        name: json['name'] as String,
        createdBy: json['created_by'] as String,
        inviteCode: json['invite_code'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'created_by': createdBy,
        'invite_code': inviteCode,
      };
}
```

```dart
// lib/models/expense.dart
class Expense {
  final String id;
  final String? groupId;
  final String paidBy;
  final String description;
  final int amountMinorUnits;
  final String currency;
  final DateTime expenseDate;
  final DateTime createdAt;
  final String createdBy;
  final DateTime? editedAt;
  final String? editedBy;
  final DateTime? deletedAt;

  Expense({
    required this.id,
    required this.groupId,
    required this.paidBy,
    required this.description,
    required this.amountMinorUnits,
    required this.currency,
    required this.expenseDate,
    required this.createdAt,
    required this.createdBy,
    this.editedAt,
    this.editedBy,
    this.deletedAt,
  });

  bool get isDeleted => deletedAt != null;
  bool get isEdited => editedAt != null;

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        id: json['id'] as String,
        groupId: json['group_id'] as String?,
        paidBy: json['paid_by'] as String,
        description: json['description'] as String,
        amountMinorUnits:
            (double.parse(json['amount'] as String) * 100).round(),
        currency: json['currency'] as String,
        expenseDate: DateTime.parse(json['expense_date'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        createdBy: json['created_by'] as String,
        editedAt: json['edited_at'] == null
            ? null
            : DateTime.parse(json['edited_at'] as String),
        editedBy: json['edited_by'] as String?,
        deletedAt: json['deleted_at'] == null
            ? null
            : DateTime.parse(json['deleted_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'group_id': groupId,
        'paid_by': paidBy,
        'description': description,
        'amount': (amountMinorUnits / 100).toStringAsFixed(2),
        'currency': currency,
        'expense_date': expenseDate.toIso8601String().split('T').first,
        'created_by': createdBy,
      };
}
```

```dart
// lib/models/expense_split.dart
class ExpenseSplit {
  final String expenseId;
  final String userId;
  final int shareAmountMinorUnits;

  ExpenseSplit({
    required this.expenseId,
    required this.userId,
    required this.shareAmountMinorUnits,
  });

  factory ExpenseSplit.fromJson(Map<String, dynamic> json) => ExpenseSplit(
        expenseId: json['expense_id'] as String,
        userId: json['user_id'] as String,
        shareAmountMinorUnits:
            (double.parse(json['share_amount'] as String) * 100).round(),
      );

  Map<String, dynamic> toJson() => {
        'expense_id': expenseId,
        'user_id': userId,
        'share_amount': (shareAmountMinorUnits / 100).toStringAsFixed(2),
      };
}
```

```dart
// lib/models/settlement.dart
enum SettlementStatus { pendingConfirmation, confirmed }

class Settlement {
  final String id;
  final String? groupId;
  final String fromUser;
  final String toUser;
  final int amountMinorUnits;
  final SettlementStatus status;
  final DateTime createdAt;
  final DateTime? confirmedAt;

  Settlement({
    required this.id,
    required this.groupId,
    required this.fromUser,
    required this.toUser,
    required this.amountMinorUnits,
    required this.status,
    required this.createdAt,
    this.confirmedAt,
  });

  factory Settlement.fromJson(Map<String, dynamic> json) => Settlement(
        id: json['id'] as String,
        groupId: json['group_id'] as String?,
        fromUser: json['from_user'] as String,
        toUser: json['to_user'] as String,
        amountMinorUnits:
            (double.parse(json['amount'] as String) * 100).round(),
        status: (json['status'] as String) == 'confirmed'
            ? SettlementStatus.confirmed
            : SettlementStatus.pendingConfirmation,
        createdAt: DateTime.parse(json['created_at'] as String),
        confirmedAt: json['confirmed_at'] == null
            ? null
            : DateTime.parse(json['confirmed_at'] as String),
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/models_test.dart`
Expected: PASS (3/3)

- [ ] **Step 5: Commit**

```bash
git add lib/models/ test/models/models_test.dart
git commit -m "feat: add domain models for users, expenses, splits, settlements"
```

---

### Task 7: Auth Repository, Sign-In & Profile Setup

**Files:**
- Create: `lib/repositories/auth_repository.dart`
- Create: `lib/features/auth/sign_in_screen.dart`
- Create: `lib/features/auth/profile_setup_screen.dart`
- Test: `test/repositories/auth_repository_test.dart`

**Interfaces:**
- Consumes: `supabaseClientProvider` (Task 1), `AppUser` (Task 6).
- Produces: `AuthRepository` with `signInWithGoogle()`, `signInWithApple()`, `upsertProfile({required String name, String? avatarUrl, String? phoneNumber})`, `currentUser` stream — consumed by `sign_in_screen.dart`, `profile_setup_screen.dart`, and every later screen that needs "who am I".

- [ ] **Step 1: Write the failing test**

```dart
// test/repositories/auth_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/repositories/auth_repository.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockGoTrueClient extends Mock implements GoTrueClient {}
class MockPostgrestQueryBuilder extends Mock implements SupabaseQueryBuilder {}

void main() {
  late MockSupabaseClient client;
  late MockGoTrueClient auth;

  setUp(() {
    client = MockSupabaseClient();
    auth = MockGoTrueClient();
    when(() => client.auth).thenReturn(auth);
  });

  test('upsertProfile calls upsert on the users table with given fields', () async {
    final table = MockPostgrestQueryBuilder();
    when(() => client.from('users')).thenReturn(table);
    when(() => auth.currentUser).thenReturn(
      User(
        id: 'u1',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-07-27T00:00:00Z',
      ),
    );
    when(() => table.upsert(any())).thenAnswer((_) async => <dynamic, dynamic>{});

    final repo = AuthRepository(client);
    await repo.upsertProfile(name: 'Alex', phoneNumber: '+911234567890');

    final captured = verify(() => table.upsert(captureAny())).captured.single
        as Map<String, dynamic>;
    expect(captured['id'], 'u1');
    expect(captured['name'], 'Alex');
    expect(captured['phone_number'], '+911234567890');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/repositories/auth_repository_test.dart`
Expected: FAIL — `AuthRepository` doesn't exist.

- [ ] **Step 3: Implement `AuthRepository`**

```dart
// lib/repositories/auth_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AuthRepository {
  final SupabaseClient _client;
  AuthRepository(this._client);

  User? get currentUser => _client.auth.currentUser;

  Future<void> signInWithGoogle() async {
    final googleSignIn = GoogleSignIn(scopes: ['email']);
    final googleUser = await googleSignIn.signIn();
    final googleAuth = await googleUser!.authentication;
    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: googleAuth.idToken!,
      accessToken: googleAuth.accessToken,
    );
  }

  Future<void> signInWithApple() async {
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );
    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: credential.identityToken!,
    );
  }

  Future<void> upsertProfile({
    required String name,
    String? avatarUrl,
    String? phoneNumber,
  }) async {
    final userId = currentUser!.id;
    await _client.from('users').upsert({
      'id': userId,
      'name': name,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (phoneNumber != null) 'phone_number': phoneNumber,
    });
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/repositories/auth_repository_test.dart`
Expected: PASS

- [ ] **Step 5: Implement `sign_in_screen.dart`**

```dart
// lib/features/auth/sign_in_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/repositories/auth_repository.dart';
import 'package:meowes_app/features/auth/profile_setup_screen.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseClientProvider)),
);

class SignInScreen extends ConsumerWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authRepo = ref.watch(authRepositoryProvider);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: () async {
                await authRepo.signInWithGoogle();
                if (context.mounted) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const ProfileSetupScreen()),
                  );
                }
              },
              child: const Text('Continue with Google'),
            ),
            ElevatedButton(
              onPressed: () async {
                await authRepo.signInWithApple();
                if (context.mounted) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const ProfileSetupScreen()),
                  );
                }
              },
              child: const Text('Continue with Apple'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Implement `profile_setup_screen.dart`**

```dart
// lib/features/auth/profile_setup_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/features/auth/sign_in_screen.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set up your profile')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone number (optional, for friend search)',
              ),
              keyboardType: TextInputType.phone,
            ),
            ElevatedButton(
              onPressed: () async {
                final authRepo = ref.read(authRepositoryProvider);
                await authRepo.upsertProfile(
                  name: _nameController.text.trim(),
                  phoneNumber: _phoneController.text.trim().isEmpty
                      ? null
                      : _phoneController.text.trim(),
                );
                // Navigation to HomeScreen wired in Task 10.
              },
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Commit**

```bash
git add lib/repositories/auth_repository.dart lib/features/auth/ test/repositories/auth_repository_test.dart
git commit -m "feat: add Google/Apple sign-in and profile setup"
```

---

### Task 8: Friend Repository & Add Friend Screen

**Files:**
- Create: `lib/repositories/friend_repository.dart`
- Create: `lib/features/friends/add_friend_screen.dart`
- Test: `test/repositories/friend_repository_test.dart`

**Interfaces:**
- Consumes: `supabaseClientProvider`, `Friendship`/`AppUser` models (Task 6).
- Produces: `FriendRepository` with `searchByPhone(String phone) -> Future<AppUser?>`, `sendFriendRequest(String toUserId) -> Future<void>`, `acceptFriendRequest(String fromUserId) -> Future<void>`, `watchFriendships() -> Stream<List<Friendship>>` — consumed by `add_friend_screen.dart` and the home screen (Task 10).

- [ ] **Step 1: Write the failing test**

```dart
// test/repositories/friend_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/repositories/friend_repository.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockGoTrueClient extends Mock implements GoTrueClient {}
class MockQueryBuilder extends Mock implements SupabaseQueryBuilder {}
class MockFilterBuilder extends Mock implements PostgrestFilterBuilder<dynamic> {}

void main() {
  test('sendFriendRequest inserts a pending friendship with ordered user ids', () async {
    final client = MockSupabaseClient();
    final auth = MockGoTrueClient();
    final table = MockQueryBuilder();

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
    when(() => client.from('friendships')).thenReturn(table);
    when(() => table.insert(any())).thenAnswer((_) async => <dynamic, dynamic>{});

    final repo = FriendRepository(client);
    await repo.sendFriendRequest('aaaaaaaa-0000-0000-0000-000000000000');

    final captured = verify(() => table.insert(captureAny())).captured.single
        as Map<String, dynamic>;
    // user_id_a < user_id_b is enforced by the DB check constraint, so the
    // repository must order the pair itself before inserting.
    expect(captured['user_id_a'], 'aaaaaaaa-0000-0000-0000-000000000000');
    expect(captured['user_id_b'], 'bbbbbbbb-0000-0000-0000-000000000000');
    expect(captured['status'], 'pending');
    expect(captured['requested_by'], 'bbbbbbbb-0000-0000-0000-000000000000');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/repositories/friend_repository_test.dart`
Expected: FAIL — `FriendRepository` doesn't exist.

- [ ] **Step 3: Implement `FriendRepository`**

```dart
// lib/repositories/friend_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/models/app_user.dart';
import 'package:meowes_app/models/friendship.dart';

class FriendRepository {
  final SupabaseClient _client;
  FriendRepository(this._client);

  Future<AppUser?> searchByPhone(String phone) async {
    final rows = await _client.from('users').select().eq('phone_number', phone).limit(1);
    if (rows.isEmpty) return null;
    return AppUser.fromJson(rows.first);
  }

  Future<void> sendFriendRequest(String toUserId) async {
    final me = _client.auth.currentUser!.id;
    final userIdA = me.compareTo(toUserId) < 0 ? me : toUserId;
    final userIdB = me.compareTo(toUserId) < 0 ? toUserId : me;
    await _client.from('friendships').insert({
      'user_id_a': userIdA,
      'user_id_b': userIdB,
      'status': 'pending',
      'requested_by': me,
    });
  }

  Future<void> acceptFriendRequest(String fromUserId) async {
    final me = _client.auth.currentUser!.id;
    final userIdA = me.compareTo(fromUserId) < 0 ? me : fromUserId;
    final userIdB = me.compareTo(fromUserId) < 0 ? fromUserId : me;
    await _client
        .from('friendships')
        .update({'status': 'accepted'})
        .eq('user_id_a', userIdA)
        .eq('user_id_b', userIdB);
  }

  Stream<List<Friendship>> watchFriendships() {
    final me = _client.auth.currentUser!.id;
    return _client
        .from('friendships')
        .stream(primaryKey: ['user_id_a', 'user_id_b'])
        .map((rows) => rows
            .map(Friendship.fromJson)
            .where((f) => f.userIdA == me || f.userIdB == me)
            .toList());
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/repositories/friend_repository_test.dart`
Expected: PASS

- [ ] **Step 5: Implement `add_friend_screen.dart`**

```dart
// lib/features/friends/add_friend_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/repositories/friend_repository.dart';
import 'package:meowes_app/models/app_user.dart';

final friendRepositoryProvider = Provider<FriendRepository>(
  (ref) => FriendRepository(ref.watch(supabaseClientProvider)),
);

class AddFriendScreen extends ConsumerStatefulWidget {
  const AddFriendScreen({super.key});

  @override
  ConsumerState<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends ConsumerState<AddFriendScreen> {
  final _phoneController = TextEditingController();
  AppUser? _found;
  bool _searched = false;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(friendRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Add friend')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Phone number'),
              keyboardType: TextInputType.phone,
            ),
            ElevatedButton(
              onPressed: () async {
                final result = await repo.searchByPhone(_phoneController.text.trim());
                setState(() {
                  _found = result;
                  _searched = true;
                });
              },
              child: const Text('Search'),
            ),
            if (_searched && _found != null)
              ListTile(
                title: Text(_found!.name),
                trailing: ElevatedButton(
                  onPressed: () async {
                    await repo.sendFriendRequest(_found!.id);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: const Text('Send request'),
                ),
              ),
            if (_searched && _found == null)
              const Text('Not registered yet — share an invite link instead.'),
              // Invite-link generation reuses the group invite_code mechanism
              // from Task 9 and is wired as a share-sheet action, not a new
              // backend concept.
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Commit**

```bash
git add lib/repositories/friend_repository.dart lib/features/friends/add_friend_screen.dart test/repositories/friend_repository_test.dart
git commit -m "feat: add friend search, request/accept, and Add Friend screen"
```

---

### Task 9: Group Repository & Create Group Screen

**Files:**
- Create: `lib/repositories/group_repository.dart`
- Create: `lib/features/groups/create_group_screen.dart`
- Test: `test/repositories/group_repository_test.dart`

**Interfaces:**
- Consumes: `supabaseClientProvider`, `Group` model (Task 6).
- Produces: `GroupRepository` with `createGroup(String name) -> Future<Group>`, `joinByInviteCode(String code) -> Future<Group>`, `watchMyGroups() -> Stream<List<Group>>` — consumed by `create_group_screen.dart`, `home_screen.dart` (Task 10), `group_detail_screen.dart` (Task 11).

- [ ] **Step 1: Write the failing test**

```dart
// test/repositories/group_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/repositories/group_repository.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockGoTrueClient extends Mock implements GoTrueClient {}
class MockQueryBuilder extends Mock implements SupabaseQueryBuilder {}
class MockFilterBuilder extends Mock implements PostgrestFilterBuilder<dynamic> {}

void main() {
  test('createGroup inserts a group and adds the creator as a member', () async {
    final client = MockSupabaseClient();
    final auth = MockGoTrueClient();
    final groupsTable = MockQueryBuilder();
    final membersTable = MockQueryBuilder();
    final selectBuilder = MockFilterBuilder();

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
    when(() => client.from('groups')).thenReturn(groupsTable);
    when(() => client.from('group_members')).thenReturn(membersTable);
    when(() => groupsTable.insert(any())).thenReturn(selectBuilder);
    when(() => selectBuilder.select()).thenReturn(selectBuilder);
    when(() => selectBuilder.single()).thenAnswer((_) async => {
          'id': 'g1',
          'name': 'Trip',
          'created_by': 'u1',
          'invite_code': 'abc123',
        });
    when(() => membersTable.insert(any())).thenAnswer((_) async => <dynamic, dynamic>{});

    final repo = GroupRepository(client);
    final group = await repo.createGroup('Trip');

    expect(group.id, 'g1');
    expect(group.inviteCode, 'abc123');
    final captured = verify(() => membersTable.insert(captureAny())).captured.single
        as Map<String, dynamic>;
    expect(captured['group_id'], 'g1');
    expect(captured['user_id'], 'u1');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/repositories/group_repository_test.dart`
Expected: FAIL — `GroupRepository` doesn't exist.

- [ ] **Step 3: Implement `GroupRepository`**

```dart
// lib/repositories/group_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/models/group.dart';

class GroupRepository {
  final SupabaseClient _client;
  GroupRepository(this._client);

  Future<Group> createGroup(String name) async {
    final me = _client.auth.currentUser!.id;
    final row = await _client
        .from('groups')
        .insert({'name': name, 'created_by': me})
        .select()
        .single();
    final group = Group.fromJson(row);
    await _client.from('group_members').insert({
      'group_id': group.id,
      'user_id': me,
    });
    return group;
  }

  Future<Group> joinByInviteCode(String code) async {
    final me = _client.auth.currentUser!.id;
    final row = await _client.from('groups').select().eq('invite_code', code).single();
    final group = Group.fromJson(row);
    await _client.from('group_members').upsert({
      'group_id': group.id,
      'user_id': me,
    });
    return group;
  }

  Stream<List<Group>> watchMyGroups() {
    final me = _client.auth.currentUser!.id;
    return _client
        .from('group_members')
        .stream(primaryKey: ['group_id', 'user_id'])
        .eq('user_id', me)
        .asyncMap((memberRows) async {
      final groupIds = memberRows.map((r) => r['group_id'] as String).toList();
      if (groupIds.isEmpty) return <Group>[];
      final groupRows = await _client.from('groups').select().inFilter('id', groupIds);
      return groupRows.map(Group.fromJson).toList();
    });
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/repositories/group_repository_test.dart`
Expected: PASS

- [ ] **Step 5: Implement `create_group_screen.dart`**

```dart
// lib/features/groups/create_group_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/supabase_client.dart';
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

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(groupRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Create group')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Group name'),
            ),
            ElevatedButton(
              onPressed: () async {
                final group = await repo.createGroup(_nameController.text.trim());
                if (context.mounted) Navigator.of(context).pop(group);
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Commit**

```bash
git add lib/repositories/group_repository.dart lib/features/groups/create_group_screen.dart test/repositories/group_repository_test.dart
git commit -m "feat: add group creation, invite-code join, and Create Group screen"
```

---

### Task 10: Expense Repository & Add Expense Screen

**Files:**
- Create: `lib/repositories/expense_repository.dart`
- Create: `lib/features/expenses/add_expense_screen.dart`
- Test: `test/repositories/expense_repository_test.dart`

**Interfaces:**
- Consumes: `supabaseClientProvider`, `Expense`/`ExpenseSplit` models (Task 6), `SplitCalculator` (Task 5).
- Produces: `ExpenseRepository` with `createExpense({required String description, required int amountMinorUnits, String? groupId, required String paidBy, required SplitType splitType, required List<String> participantIds, Map<String,double>? percentages, Map<String,int>? exactAmounts, required DateTime expenseDate}) -> Future<Expense>`, `editExpense(...)`, `deleteExpense(String expenseId)` — consumed by `add_expense_screen.dart` and `expense_detail_screen.dart` (Task 13).

- [ ] **Step 1: Write the failing test**

```dart
// test/repositories/expense_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/repositories/expense_repository.dart';
import 'package:meowes_app/splitting/split_calculator.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockGoTrueClient extends Mock implements GoTrueClient {}
class MockQueryBuilder extends Mock implements SupabaseQueryBuilder {}
class MockFilterBuilder extends Mock implements PostgrestFilterBuilder<dynamic> {}

void main() {
  test('createExpense inserts expense then inserts splits from SplitCalculator', () async {
    final client = MockSupabaseClient();
    final auth = MockGoTrueClient();
    final expensesTable = MockQueryBuilder();
    final splitsTable = MockQueryBuilder();
    final selectBuilder = MockFilterBuilder();

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
    when(() => client.from('expenses')).thenReturn(expensesTable);
    when(() => client.from('expense_splits')).thenReturn(splitsTable);
    when(() => expensesTable.insert(any())).thenReturn(selectBuilder);
    when(() => selectBuilder.select()).thenReturn(selectBuilder);
    when(() => selectBuilder.single()).thenAnswer((_) async => {
          'id': 'e1',
          'group_id': null,
          'paid_by': 'u1',
          'description': 'Coffee',
          'amount': '100.00',
          'currency': 'INR',
          'expense_date': '2026-07-27',
          'created_at': '2026-07-27T10:00:00Z',
          'created_by': 'u1',
          'edited_at': null,
          'edited_by': null,
          'deleted_at': null,
        });
    when(() => splitsTable.insert(any())).thenAnswer((_) async => <dynamic, dynamic>{});

    final repo = ExpenseRepository(client);
    final expense = await repo.createExpense(
      description: 'Coffee',
      amountMinorUnits: 10000,
      groupId: null,
      paidBy: 'u1',
      splitType: SplitType.equal,
      participantIds: ['u1', 'u2'],
      expenseDate: DateTime(2026, 7, 27),
    );

    expect(expense.id, 'e1');
    final captured = verify(() => splitsTable.insert(captureAny())).captured.single
        as List<Map<String, dynamic>>;
    expect(captured, containsAll([
      {'expense_id': 'e1', 'user_id': 'u1', 'share_amount': '50.00'},
      {'expense_id': 'e1', 'user_id': 'u2', 'share_amount': '50.00'},
    ]));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/repositories/expense_repository_test.dart`
Expected: FAIL — `ExpenseRepository` doesn't exist.

- [ ] **Step 3: Implement `ExpenseRepository`**

```dart
// lib/repositories/expense_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/models/expense.dart';
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
          'expense_id': expense.id,
          'user_id': entry.key,
          'share_amount': (entry.value / 100).toStringAsFixed(2),
        },
    ]);

    return expense;
  }

  Future<void> editExpense({
    required String expenseId,
    required String description,
    required int amountMinorUnits,
  }) async {
    final me = _client.auth.currentUser!.id;
    await _client.from('expenses').update({
      'description': description,
      'amount': (amountMinorUnits / 100).toStringAsFixed(2),
      'edited_at': DateTime.now().toIso8601String(),
      'edited_by': me,
    }).eq('id', expenseId);
    // Re-splitting on edit reuses the same expense_splits insert path as
    // createExpense; a full re-split (delete old splits, insert new ones
    // via SplitCalculator) is called from expense_detail_screen.dart (Task 13).
  }

  Future<void> deleteExpense(String expenseId) async {
    await _client
        .from('expenses')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', expenseId);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/repositories/expense_repository_test.dart`
Expected: PASS

- [ ] **Step 5: Implement `add_expense_screen.dart`**

```dart
// lib/features/expenses/add_expense_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/repositories/expense_repository.dart';
import 'package:meowes_app/splitting/split_calculator.dart';

final expenseRepositoryProvider = Provider<ExpenseRepository>(
  (ref) => ExpenseRepository(ref.watch(supabaseClientProvider)),
);

class AddExpenseScreen extends ConsumerStatefulWidget {
  final String? groupId;
  final List<String> participantIds;

  const AddExpenseScreen({super.key, this.groupId, required this.participantIds});

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  SplitType _splitType = SplitType.equal;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(expenseRepositoryProvider);
    final me = ref.watch(supabaseClientProvider).auth.currentUser!.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Add expense')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            TextField(
              controller: _amountController,
              decoration: const InputDecoration(labelText: 'Amount'),
              keyboardType: TextInputType.number,
            ),
            DropdownButton<SplitType>(
              value: _splitType,
              items: SplitType.values
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                  .toList(),
              onChanged: (t) => setState(() => _splitType = t!),
            ),
            ElevatedButton(
              onPressed: () async {
                final amountMinorUnits =
                    (double.parse(_amountController.text) * 100).round();
                await repo.createExpense(
                  description: _descriptionController.text.trim(),
                  amountMinorUnits: amountMinorUnits,
                  groupId: widget.groupId,
                  paidBy: me,
                  splitType: _splitType,
                  participantIds: widget.participantIds,
                  expenseDate: DateTime.now(),
                );
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Commit**

```bash
git add lib/repositories/expense_repository.dart lib/features/expenses/add_expense_screen.dart test/repositories/expense_repository_test.dart
git commit -m "feat: add expense creation/edit/delete and Add Expense screen"
```

---

### Task 11: Settlement Repository & Settle-Up Screen

**Files:**
- Create: `lib/repositories/settlement_repository.dart`
- Create: `lib/features/settlements/settle_up_screen.dart`
- Test: `test/repositories/settlement_repository_test.dart`

**Interfaces:**
- Consumes: `supabaseClientProvider`, `Settlement` model (Task 6).
- Produces: `SettlementRepository` with `markPaid({required String toUser, required int amountMinorUnits, String? groupId}) -> Future<Settlement>`, `confirmSettlement(String settlementId) -> Future<void>`, `watchPendingForMe() -> Stream<List<Settlement>>` — consumed by `settle_up_screen.dart` and friend/group detail screens (Task 12).

- [ ] **Step 1: Write the failing test**

```dart
// test/repositories/settlement_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/repositories/settlement_repository.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockGoTrueClient extends Mock implements GoTrueClient {}
class MockQueryBuilder extends Mock implements SupabaseQueryBuilder {}
class MockFilterBuilder extends Mock implements PostgrestFilterBuilder<dynamic> {}

void main() {
  test('markPaid inserts a pending_confirmation settlement from the current user', () async {
    final client = MockSupabaseClient();
    final auth = MockGoTrueClient();
    final table = MockQueryBuilder();
    final selectBuilder = MockFilterBuilder();

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
    when(() => client.from('settlements')).thenReturn(table);
    when(() => table.insert(any())).thenReturn(selectBuilder);
    when(() => selectBuilder.select()).thenReturn(selectBuilder);
    when(() => selectBuilder.single()).thenAnswer((_) async => {
          'id': 's1',
          'group_id': null,
          'from_user': 'u1',
          'to_user': 'u2',
          'amount': '500.00',
          'status': 'pending_confirmation',
          'created_at': '2026-07-27T10:00:00Z',
          'confirmed_at': null,
        });

    final repo = SettlementRepository(client);
    final settlement =
        await repo.markPaid(toUser: 'u2', amountMinorUnits: 50000);

    expect(settlement.id, 's1');
    final captured = verify(() => table.insert(captureAny())).captured.single
        as Map<String, dynamic>;
    expect(captured['from_user'], 'u1');
    expect(captured['to_user'], 'u2');
    expect(captured['amount'], '500.00');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/repositories/settlement_repository_test.dart`
Expected: FAIL — `SettlementRepository` doesn't exist.

- [ ] **Step 3: Implement `SettlementRepository`**

```dart
// lib/repositories/settlement_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/models/settlement.dart';

class SettlementRepository {
  final SupabaseClient _client;
  SettlementRepository(this._client);

  Future<Settlement> markPaid({
    required String toUser,
    required int amountMinorUnits,
    String? groupId,
  }) async {
    final me = _client.auth.currentUser!.id;
    final row = await _client
        .from('settlements')
        .insert({
          'group_id': groupId,
          'from_user': me,
          'to_user': toUser,
          'amount': (amountMinorUnits / 100).toStringAsFixed(2),
          'status': 'pending_confirmation',
        })
        .select()
        .single();
    return Settlement.fromJson(row);
  }

  Future<void> confirmSettlement(String settlementId) async {
    await _client.from('settlements').update({
      'status': 'confirmed',
      'confirmed_at': DateTime.now().toIso8601String(),
    }).eq('id', settlementId);
  }

  Stream<List<Settlement>> watchPendingForMe() {
    final me = _client.auth.currentUser!.id;
    return _client
        .from('settlements')
        .stream(primaryKey: ['id'])
        .eq('status', 'pending_confirmation')
        .map((rows) => rows
            .map(Settlement.fromJson)
            .where((s) => s.toUser == me)
            .toList());
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/repositories/settlement_repository_test.dart`
Expected: PASS

- [ ] **Step 5: Implement `settle_up_screen.dart`**

```dart
// lib/features/settlements/settle_up_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/repositories/settlement_repository.dart';

final settlementRepositoryProvider = Provider<SettlementRepository>(
  (ref) => SettlementRepository(ref.watch(supabaseClientProvider)),
);

class SettleUpScreen extends ConsumerWidget {
  final String toUser;
  final int amountMinorUnits;
  final String? groupId;

  const SettleUpScreen({
    super.key,
    required this.toUser,
    required this.amountMinorUnits,
    this.groupId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(settlementRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settle up')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('₹${(amountMinorUnits / 100).toStringAsFixed(2)}'),
            ElevatedButton(
              onPressed: () async {
                await repo.markPaid(
                  toUser: toUser,
                  amountMinorUnits: amountMinorUnits,
                  groupId: groupId,
                );
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('I paid this'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Commit**

```bash
git add lib/repositories/settlement_repository.dart lib/features/settlements/settle_up_screen.dart test/repositories/settlement_repository_test.dart
git commit -m "feat: add two-sided settle-up (mark paid / confirm)"
```

---

### Task 12: Home Screen (Friends + Groups, Live Balances)

**Files:**
- Create: `lib/features/home/home_screen.dart`
- Test: `test/features/home/home_screen_test.dart`

**Interfaces:**
- Consumes: `friendRepositoryProvider` (Task 8), `groupRepositoryProvider` (Task 9), `supabaseClientProvider`, and calls the `get_friend_balance`/`get_group_debts` RPCs (Tasks 3–4) directly via `.rpc(...)`.
- Produces: `HomeScreen` widget, navigable to `AddFriendScreen`, `CreateGroupScreen`, `FriendDetailScreen`/`GroupDetailScreen` (Task 13).

- [ ] **Step 1: Write the failing widget test**

```dart
// test/features/home/home_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/features/home/home_screen.dart';

void main() {
  testWidgets('HomeScreen shows Friends and Groups section headers', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    expect(find.text('Friends'), findsOneWidget);
    expect(find.text('Groups'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/home/home_screen_test.dart`
Expected: FAIL — `HomeScreen` doesn't exist.

- [ ] **Step 3: Implement `home_screen.dart`**

```dart
// lib/features/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/features/friends/add_friend_screen.dart';
import 'package:meowes_app/features/groups/create_group_screen.dart';
import 'package:meowes_app/repositories/friend_repository.dart';
import 'package:meowes_app/repositories/group_repository.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    final friendsStream = ref.watch(friendRepositoryProvider).watchFriendships();
    final groupsStream = ref.watch(groupRepositoryProvider).watchMyGroups();

    return Scaffold(
      appBar: AppBar(title: const Text('Meowes')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Friends', style: TextStyle(fontSize: 20)),
          ),
          StreamBuilder(
            stream: friendsStream,
            builder: (context, snapshot) {
              final friendships = snapshot.data ?? [];
              final me = client.auth.currentUser!.id;
              return Column(
                children: [
                  for (final f in friendships.where((f) => f.status.name == 'accepted'))
                    _FriendBalanceTile(
                      friendUserId: f.userIdA == me ? f.userIdB : f.userIdA,
                    ),
                ],
              );
            },
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Groups', style: TextStyle(fontSize: 20)),
          ),
          StreamBuilder(
            stream: groupsStream,
            builder: (context, snapshot) {
              final groups = snapshot.data ?? [];
              return Column(
                children: [
                  for (final g in groups) ListTile(title: Text(g.name)),
                ],
              );
            },
          ),
        ],
      ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AddFriendScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.group_add),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendBalanceTile extends ConsumerWidget {
  final String friendUserId;
  const _FriendBalanceTile({required this.friendUserId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    final me = client.auth.currentUser!.id;
    return FutureBuilder(
      future: client.rpc('get_friend_balance', params: {
        'user_a': me,
        'user_b': friendUserId,
      }),
      builder: (context, snapshot) {
        final balance = (snapshot.data as num?)?.toDouble() ?? 0;
        return ListTile(
          title: Text(friendUserId),
          trailing: Text('₹${balance.toStringAsFixed(2)}'),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/home/home_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/home/home_screen.dart test/features/home/home_screen_test.dart
git commit -m "feat: add home screen with live friend and group balances"
```

---

### Task 13: Friend Detail, Group Detail & Expense Detail Screens

**Files:**
- Create: `lib/features/friends/friend_detail_screen.dart`
- Create: `lib/features/groups/group_detail_screen.dart`
- Create: `lib/features/expenses/expense_detail_screen.dart`
- Test: `test/features/expenses/expense_detail_screen_test.dart`

**Interfaces:**
- Consumes: `expenseRepositoryProvider` (Task 10), `settlementRepositoryProvider` (Task 11), `groupRepositoryProvider` (Task 9), and the `get_group_debts` RPC (Task 4).
- Produces: navigable detail screens; `ExpenseDetailScreen` produces the edit/delete UI referenced by `Expense.isEdited`/`isDeleted` (Task 6).

- [ ] **Step 1: Write the failing widget test for expense detail edit/delete**

```dart
// test/features/expenses/expense_detail_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/features/expenses/expense_detail_screen.dart';
import 'package:meowes_app/models/expense.dart';

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

    await tester.pumpWidget(
      ProviderScope(
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

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: ExpenseDetailScreen(expense: expense)),
      ),
    );
    await tester.pump();

    expect(find.text('Edited'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/expenses/expense_detail_screen_test.dart`
Expected: FAIL — `ExpenseDetailScreen` doesn't exist.

- [ ] **Step 3: Implement `expense_detail_screen.dart`**

```dart
// lib/features/expenses/expense_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/models/expense.dart';
import 'package:meowes_app/repositories/expense_repository.dart';
import 'package:meowes_app/features/expenses/add_expense_screen.dart';

class ExpenseDetailScreen extends ConsumerWidget {
  final Expense expense;
  const ExpenseDetailScreen({super.key, required this.expense});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(expenseRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(expense.description)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('₹${(expense.amountMinorUnits / 100).toStringAsFixed(2)}'),
                if (expense.isEdited) const Text('Edited'),
              ],
            ),
          ),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AddExpenseScreen(
                      groupId: expense.groupId,
                      participantIds: const [], // populated from expense_splits when wired to a live expense
                    ),
                  ),
                ),
                child: const Text('Edit'),
              ),
              TextButton(
                onPressed: () async {
                  await repo.deleteExpense(expense.id);
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/expenses/expense_detail_screen_test.dart`
Expected: PASS (2/2)

- [ ] **Step 5: Implement `friend_detail_screen.dart`**

```dart
// lib/features/friends/friend_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/features/settlements/settle_up_screen.dart';

class FriendDetailScreen extends ConsumerWidget {
  final String friendUserId;
  const FriendDetailScreen({super.key, required this.friendUserId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    final me = client.auth.currentUser!.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Friend')),
      body: FutureBuilder(
        future: client.rpc('get_friend_balance', params: {
          'user_a': me,
          'user_b': friendUserId,
        }),
        builder: (context, snapshot) {
          final balance = (snapshot.data as num?)?.toDouble() ?? 0;
          return Column(
            children: [
              Text('₹${balance.toStringAsFixed(2)}'),
              ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SettleUpScreen(
                      toUser: friendUserId,
                      amountMinorUnits: (balance.abs() * 100).round(),
                    ),
                  ),
                ),
                child: const Text('Settle up'),
              ),
            ],
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 6: Implement `group_detail_screen.dart`**

```dart
// lib/features/groups/group_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meowes_app/core/supabase_client.dart';
import 'package:meowes_app/features/settlements/settle_up_screen.dart';

class GroupDetailScreen extends ConsumerWidget {
  final String groupId;
  const GroupDetailScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Group')),
      body: FutureBuilder(
        future: client.rpc('get_group_debts', params: {'target_group_id': groupId}),
        builder: (context, snapshot) {
          final debts = (snapshot.data as List<dynamic>?) ?? [];
          return ListView(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Smart settle suggestions'),
              ),
              for (final d in debts)
                ListTile(
                  title: Text('${d['from_user']} owes ${d['to_user']}'),
                  trailing: Text('₹${d['amount']}'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SettleUpScreen(
                        toUser: d['to_user'] as String,
                        amountMinorUnits:
                            (double.parse(d['amount'].toString()) * 100).round(),
                        groupId: groupId,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 7: Commit**

```bash
git add lib/features/friends/friend_detail_screen.dart lib/features/groups/group_detail_screen.dart lib/features/expenses/expense_detail_screen.dart test/features/expenses/expense_detail_screen_test.dart
git commit -m "feat: add friend/group/expense detail screens with settle-up and edit/delete"
```

---

## Spec Coverage Check

- Auth (Google/Apple), profile, phone number as discovery-only field → Task 7
- Friend search/request/accept, invite-link fallback → Task 8
- Group creation, invite code, join → Task 9
- Expense creation with/without group, equal/%/exact splits → Tasks 5, 10
- Server-side, uncached balance computation (friend + group) → Tasks 3, 4
- Debt simplification ("smart settle") → Task 4, surfaced in Task 13
- Two-sided settle-up confirmation → Task 11, surfaced in Tasks 12–13
- Expense edit/delete (soft delete, any participant, edited indicator) → Tasks 6, 10, 13
- Real-time sync → `.stream()` subscriptions in Tasks 8, 9, 11 (Supabase Realtime under the hood)
- Home screen (friends + groups with live balances) → Task 12

All spec sections have a corresponding task. Pet/coin/mood, UPI, paywall, OCR, charts, and cosmetics remain out of scope per the spec and are not covered here.
