-- groups_select_member RLS (0001_init_schema.sql) requires being a group
-- member to SELECT a group row at all — which makes plain client-side
-- "look up by invite_code, then insert my membership" impossible: a
-- non-member can never see the row to join it in the first place. This
-- SECURITY DEFINER function looks up the group and inserts the caller's
-- membership atomically, bypassing RLS internally (safe here because
-- knowing the invite code is itself the authorization to join).
create or replace function join_group_by_code(invite_code_param text)
returns setof groups
language plpgsql
security definer
set search_path = public
as $$
declare
  target_group groups%rowtype;
begin
  select * into target_group from groups where invite_code = invite_code_param;

  if not found then
    raise exception 'invalid invite code';
  end if;

  insert into group_members (group_id, user_id)
  values (target_group.id, auth.uid())
  on conflict (group_id, user_id) do nothing;

  return next target_group;
end;
$$;

revoke all on function join_group_by_code(text) from public;
grant execute on function join_group_by_code(text) to authenticated;
