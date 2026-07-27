-- The prior migration fixed group_members' self-recursion but left a
-- second, cross-table recursion: expenses_select_participant queries
-- expense_splits (to check "do I have a split on this expense"), and
-- expense_splits_select_participant queries expenses right back (to check
-- "am I the payer/creator/group-member of this expense's row") — each
-- table's SELECT policy triggers the other's, forming a two-table cycle.
-- Confirmed via direct reproduction: calling get_group_debts as a real
-- authenticated user threw "infinite recursion detected in policy for
-- relation expense_splits".
--
-- Same fix as before: SECURITY DEFINER helpers whose internal queries
-- bypass RLS, breaking both cross-table cycles.
create or replace function has_expense_split(p_expense_id uuid, p_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from expense_splits es
    where es.expense_id = p_expense_id and es.user_id = p_user_id
  );
$$;

create or replace function is_expense_owner(p_expense_id uuid, p_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from expenses e
    where e.id = p_expense_id and (e.paid_by = p_user_id or e.created_by = p_user_id)
  );
$$;

create or replace function is_expense_owner_or_group_member(p_expense_id uuid, p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_paid_by uuid;
  v_created_by uuid;
  v_group_id uuid;
begin
  select paid_by, created_by, group_id into v_paid_by, v_created_by, v_group_id
  from expenses where id = p_expense_id;

  if not found then
    return false;
  end if;

  return v_paid_by = p_user_id
    or v_created_by = p_user_id
    or (v_group_id is not null and is_group_member(v_group_id, p_user_id));
end;
$$;

revoke all on function has_expense_split(uuid, uuid) from public;
revoke all on function is_expense_owner(uuid, uuid) from public;
revoke all on function is_expense_owner_or_group_member(uuid, uuid) from public;
grant execute on function has_expense_split(uuid, uuid) to authenticated;
grant execute on function is_expense_owner(uuid, uuid) to authenticated;
grant execute on function is_expense_owner_or_group_member(uuid, uuid) to authenticated;

drop policy if exists expenses_select_participant on expenses;
create policy expenses_select_participant on expenses
  for select to authenticated using (
    paid_by = auth.uid()
    or created_by = auth.uid()
    or has_expense_split(id, auth.uid())
    or (group_id is not null and is_group_member(expenses.group_id, auth.uid()))
  );

drop policy if exists expenses_update_participant on expenses;
create policy expenses_update_participant on expenses
  for update to authenticated using (
    paid_by = auth.uid()
    or created_by = auth.uid()
    or has_expense_split(id, auth.uid())
  );

drop policy if exists expense_splits_select_participant on expense_splits;
create policy expense_splits_select_participant on expense_splits
  for select to authenticated using (
    user_id = auth.uid()
    or is_expense_owner_or_group_member(expense_id, auth.uid())
  );

drop policy if exists expense_splits_insert_participant on expense_splits;
create policy expense_splits_insert_participant on expense_splits
  for insert to authenticated with check (
    is_expense_owner(expense_id, auth.uid())
  );

drop policy if exists expense_splits_update_participant on expense_splits;
create policy expense_splits_update_participant on expense_splits
  for update to authenticated using (
    is_expense_owner(expense_id, auth.uid())
  );

drop policy if exists expense_splits_delete_participant on expense_splits;
create policy expense_splits_delete_participant on expense_splits
  for delete to authenticated using (
    is_expense_owner(expense_id, auth.uid())
  );
