-- Fix 1 & 2: expense_splits policies were payer-only (missed created_by and
-- group-mate participants) and had no update/delete policy at all, which
-- would silently block "I logged an expense someone else paid" and expense
-- editing (re-splitting requires deleting/updating old split rows).

drop policy if exists expense_splits_select_participant on expense_splits;
create policy expense_splits_select_participant on expense_splits
  for select to authenticated using (
    user_id = auth.uid()
    or exists (
      select 1 from expenses e
      where e.id = expense_id
        and (
          e.paid_by = auth.uid()
          or e.created_by = auth.uid()
          or (e.group_id is not null and exists (
            select 1 from group_members gm where gm.group_id = e.group_id and gm.user_id = auth.uid()
          ))
        )
    )
  );

drop policy if exists expense_splits_insert_payer on expense_splits;
create policy expense_splits_insert_participant on expense_splits
  for insert to authenticated with check (
    exists (
      select 1 from expenses e
      where e.id = expense_id
        and (e.paid_by = auth.uid() or e.created_by = auth.uid())
    )
  );

create policy expense_splits_update_participant on expense_splits
  for update to authenticated using (
    exists (
      select 1 from expenses e
      where e.id = expense_id
        and (e.paid_by = auth.uid() or e.created_by = auth.uid())
    )
  );

create policy expense_splits_delete_participant on expense_splits
  for delete to authenticated using (
    exists (
      select 1 from expenses e
      where e.id = expense_id
        and (e.paid_by = auth.uid() or e.created_by = auth.uid())
    )
  );

-- Fix 3: users_select_authenticated (using(true)) let any authenticated user
-- read every user's phone_number, not just numbers they actually searched
-- for. Lock the base table to own-row-only, and expose non-sensitive
-- profile fields (name, avatar) to any authenticated user via a view —
-- needed so friends'/group-mates' names still display without exposing
-- phone_number table-wide. Phone lookup moves to a SECURITY DEFINER RPC
-- that returns only what's needed to send a friend request, never the
-- phone number itself.

drop policy if exists users_select_authenticated on users;
create policy users_select_self on users
  for select to authenticated using (id = auth.uid());

create view public_profiles
  with (security_invoker = false) as
  select id, name, avatar_url from users;

grant select on public_profiles to authenticated;

create or replace function find_user_by_phone(p_phone text)
returns table(id uuid, name text, avatar_url text)
language sql
security definer
set search_path = public
stable
as $$
  select u.id, u.name, u.avatar_url
  from users u
  where u.phone_number = p_phone;
$$;

revoke all on function find_user_by_phone(text) from public;
grant execute on function find_user_by_phone(text) to authenticated;
