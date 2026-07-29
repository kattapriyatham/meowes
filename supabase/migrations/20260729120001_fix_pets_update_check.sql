drop policy pets_update_owner on pets;

create policy pets_update_owner on pets
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
