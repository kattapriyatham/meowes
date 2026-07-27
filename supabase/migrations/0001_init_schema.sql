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
  invite_code text not null unique default substring(md5(random()::text), 1, 12),
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
