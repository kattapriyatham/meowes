-- friendships_update_party let EITHER party update a friendship row,
-- including the requester themselves — so a client could self-accept
-- their own pending request (insert pending, then immediately update it
-- to accepted), bypassing the "requires accept from the other party"
-- constraint entirely. Also, friendships_insert_party placed no
-- constraint on the inserted status, so a client could insert a row as
-- 'accepted' outright. No Dart code path does either today (sendFriendRequest
-- always inserts 'pending', acceptFriendRequest is the only updater), but
-- the RLS layer should enforce this itself rather than relying on client
-- convention — the settlements table already gets this right
-- (settlements_update_payee_confirms restricts to to_user only); friendships
-- should mirror that pattern.
drop policy if exists friendships_insert_party on friendships;
create policy friendships_insert_party on friendships
  for insert to authenticated with check (
    (auth.uid() = user_id_a or auth.uid() = user_id_b)
    and status = 'pending'
  );

drop policy if exists friendships_update_party on friendships;
create policy friendships_update_party on friendships
  for update to authenticated using (
    (auth.uid() = user_id_a or auth.uid() = user_id_b)
    and auth.uid() <> requested_by
  );
