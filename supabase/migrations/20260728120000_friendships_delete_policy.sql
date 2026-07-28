-- friendships had no delete policy at all (only select/insert/update),
-- so there was no way to decline a pending request — the row would just
-- sit there forever. Either party to the friendship may delete it.
create policy friendships_delete_party on friendships
  for delete to authenticated using (
    auth.uid() = user_id_a or auth.uid() = user_id_b
  );
