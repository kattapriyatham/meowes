-- Personal invite links: each user gets a stable bearer-secret invite_code
-- (same pattern as groups.invite_code — knowing the code is itself the
-- authorization to use it), so friends can be added by sharing a link
-- instead of only phone-number search.
alter table users
  add column invite_code text not null unique default encode(extensions.gen_random_bytes(6), 'hex');

-- Redeeming a code creates an already-accepted friendship directly,
-- mirroring join_group_by_code's no-approval-step join: generating and
-- sharing the link is the inviter's consent, using it is the invitee's, so
-- there's no need for the pending -> accept round trip phone-search
-- requests go through (friendships_insert_party only allows inserting
-- status = 'pending' directly). SECURITY DEFINER because users_select_self
-- blocks a stranger from ever seeing the inviter's row to look up their id
-- otherwise — same reasoning as find_user_by_phone.
create or replace function join_friendship_by_code(invite_code_param text)
returns table(id uuid, name text, avatar_url text)
language plpgsql
security definer
set search_path = public
as $$
declare
  target_user_id uuid;
  v_user_id_a uuid;
  v_user_id_b uuid;
begin
  select u.id into target_user_id from users u where u.invite_code = invite_code_param;

  if not found then
    raise exception 'invalid_invite_code';
  end if;

  if target_user_id = auth.uid() then
    raise exception 'cannot_friend_self';
  end if;

  v_user_id_a := least(auth.uid(), target_user_id);
  v_user_id_b := greatest(auth.uid(), target_user_id);

  insert into friendships (user_id_a, user_id_b, status, requested_by)
  values (v_user_id_a, v_user_id_b, 'accepted', auth.uid())
  on conflict (user_id_a, user_id_b) do update set status = 'accepted';

  return query select u.id, u.name, u.avatar_url from users u where u.id = target_user_id;
end;
$$;
revoke all on function join_friendship_by_code(text) from public;
grant execute on function join_friendship_by_code(text) to authenticated;
