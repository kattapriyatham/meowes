-- Account deletion (App Store Guideline 5.1.1(v) / Play account-deletion policy).
--
-- Strategy: ANONYMISE + KEEP SHARED HISTORY.
-- A user's expenses and confirmed settlements are financial records that the
-- *other* party still relies on for their balances, so we don't delete them.
-- Instead we:
--   * scrub the `users` row to an unnamed "Deleted user" tombstone,
--   * delete everything personal that only concerns the leaving user
--     (friendships, device tokens, pet + pet data, group memberships,
--      still-unconfirmed settlements),
--   * delete the Supabase auth record so the account can never sign in again.
--
-- Deleting `auth.users` would normally cascade to `public.users` (and then be
-- blocked by the RESTRICT FKs on expenses/settlements). We drop that FK so the
-- scrubbed tombstone row survives independently. New signups still create their
-- `users` row client-side keyed on `auth.uid()`, so nothing else changes.

alter table users add column if not exists deleted_at timestamptz;

alter table users drop constraint if exists users_id_fkey;

create or replace function delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  -- 1. Scrub the profile to an anonymous tombstone. Kept (not deleted) so
  --    expenses / confirmed settlements that reference it still render a
  --    name for the remaining participants.
  update users
     set name = 'Deleted user',
         phone_number = null,
         avatar_url = null,
         deleted_at = now()
   where id = v_uid;

  -- 2. Personal data that only concerns this user.
  delete from friendships   where user_id_a = v_uid or user_id_b = v_uid;
  delete from device_tokens where user_id = v_uid;
  delete from group_members where user_id = v_uid;
  delete from food_inventory where user_id = v_uid;
  delete from pet_memories  where user_id = v_uid;
  delete from pets          where user_id = v_uid;

  -- 3. Settlements the counterparty never confirmed can no longer be actioned
  --    by anyone, so drop them. Confirmed ones are real history — keep them.
  delete from settlements
   where status = 'pending_confirmation'
     and (from_user = v_uid or to_user = v_uid);

  -- 4. Remove the auth identity so the account is gone for good. auth.sessions
  --    and auth.refresh_tokens cascade from auth.users.
  delete from auth.identities where user_id = v_uid;
  delete from auth.users      where id = v_uid;
end;
$$;

revoke all on function delete_my_account() from public;
grant execute on function delete_my_account() to authenticated;
