-- group_members_select_fellow_member (0001_init_schema.sql) checks group
-- membership via a correlated subquery directly on group_members — but
-- that subquery is itself subject to group_members' own SELECT policy,
-- which runs the same subquery again, and so on: confirmed via direct
-- reproduction (`set local role authenticated` + a real JWT sub claim)
-- that this throws "infinite recursion detected in policy for relation
-- group_members". groups_select_member, groups_update_member,
-- expenses_select_participant, and expense_splits_select_participant all
-- have the same structural issue (a raw correlated subquery on
-- group_members inside their USING clause), which would recurse into the
-- same broken policy.
--
-- Standard fix: a SECURITY DEFINER helper function. Its internal query
-- against group_members runs as the function owner, bypassing RLS
-- entirely, so it can't recurse — while still being safe to expose to any
-- authenticated caller, since it only ever answers "is X a member of Y",
-- never returning row contents beyond that boolean.
create or replace function is_group_member(p_group_id uuid, p_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from group_members gm
    where gm.group_id = p_group_id and gm.user_id = p_user_id
  );
$$;

revoke all on function is_group_member(uuid, uuid) from public;
grant execute on function is_group_member(uuid, uuid) to authenticated;

drop policy if exists group_members_select_fellow_member on group_members;
create policy group_members_select_fellow_member on group_members
  for select to authenticated using (
    is_group_member(group_members.group_id, auth.uid())
  );

drop policy if exists groups_select_member on groups;
create policy groups_select_member on groups
  for select to authenticated using (
    is_group_member(id, auth.uid())
  );

drop policy if exists groups_update_member on groups;
create policy groups_update_member on groups
  for update to authenticated using (
    is_group_member(id, auth.uid())
  );

drop policy if exists expenses_select_participant on expenses;
create policy expenses_select_participant on expenses
  for select to authenticated using (
    paid_by = auth.uid()
    or created_by = auth.uid()
    or exists (select 1 from expense_splits es where es.expense_id = id and es.user_id = auth.uid())
    or (group_id is not null and is_group_member(expenses.group_id, auth.uid()))
  );

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
          or (e.group_id is not null and is_group_member(e.group_id, auth.uid()))
        )
    )
  );

-- createGroup's insert().select().single() pattern has a separate, real bug:
-- at the moment the groups row is inserted and its RETURNING/select clause
-- evaluated, the creator has not yet been added to group_members (that's a
-- second, later statement in the Dart repository) — so groups_select_member
-- (member-only SELECT) filters out the very row just inserted, and .single()
-- gets zero rows. Group creation and adding the creator as a member must
-- happen atomically in one SECURITY DEFINER function, same pattern as
-- join_group_by_code.
create or replace function create_group(p_name text)
returns setof groups
language plpgsql
security definer
set search_path = public
as $$
declare
  new_group groups%rowtype;
begin
  insert into groups (name, created_by)
  values (p_name, auth.uid())
  returning * into new_group;

  insert into group_members (group_id, user_id)
  values (new_group.id, auth.uid());

  return next new_group;
end;
$$;

revoke all on function create_group(text) from public;
grant execute on function create_group(text) to authenticated;
