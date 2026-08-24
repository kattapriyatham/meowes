-- Special foods: purchasable food items with coin cost and limited uses.
-- Unlike regular foods (fish/treats/dry food), these are bought with coins
-- and have limited inventory per purchase.
create table special_foods (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  name text not null,
  coin_cost integer not null check (coin_cost > 0),
  uses_per_purchase integer not null default 1 check (uses_per_purchase > 0),
  satiation_hours integer not null default 6,
  coin_reward integer not null default 5,
  bowl_asset text not null,
  description text not null
);

alter table special_foods enable row level security;

create policy special_foods_select_all on special_foods
  for select to authenticated using (true);

insert into special_foods (key, name, coin_cost, uses_per_purchase, satiation_hours, coin_reward, bowl_asset, description) values
  ('premium_fish', 'Premium Fish', 50, 3, 8, 8, 'assets/images/pet/bowl_premium_fish.png', 'High-quality fish that keeps your cat full longer and boosts happiness.'),
  ('gourmet_treats', 'Gourmet Treats', 30, 5, 4, 4, 'assets/images/pet/bowl_gourmet_treats.png', 'Special treats your cat loves. More uses, shorter satisfaction.'),
  ('fancy_feast', 'Fancy Feast', 100, 2, 12, 15, 'assets/images/pet/bowl_fancy_feast.png', 'A luxurious meal. Maximum happiness, maximum satisfaction.');

-- User inventory of purchased special foods.
create table food_inventory (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  special_food_id uuid not null references special_foods(id) on delete cascade,
  uses_remaining integer not null check (uses_remaining > 0),
  purchased_at timestamptz not null default now(),
  last_used_at timestamptz
);

create index idx_food_inventory_user on food_inventory(user_id, special_food_id);

alter table food_inventory enable row level security;

create policy food_inventory_select_owner on food_inventory
  for select to authenticated using (auth.uid() = user_id);

create policy food_inventory_insert_owner on food_inventory
  for insert to authenticated with check (auth.uid() = user_id);

create policy food_inventory_update_owner on food_inventory
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy food_inventory_delete_owner on food_inventory
  for delete to authenticated using (auth.uid() = user_id);

-- Per-special-food cooldown tracking.
alter table pets add column last_special_fed_at timestamptz;
alter table pets add column last_special_food_id uuid;

-- Purchase a special food: deduct coins, add to inventory.
create or replace function purchase_special_food(p_special_food_id uuid)
returns food_inventory
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pet pets;
  v_food special_foods;
  v_inventory food_inventory;
begin
  perform get_or_create_pet();

  select * into v_pet from pets where user_id = auth.uid() for update;
  select * into v_food from special_foods where id = p_special_food_id;

  if v_food is null then
    raise exception 'special_food_not_found';
  end if;

  if v_pet.coins < v_food.coin_cost then
    raise exception 'insufficient_coins';
  end if;

  -- Deduct coins
  update pets set coins = coins - v_food.coin_cost where user_id = auth.uid();

  -- Add to inventory
  insert into food_inventory (user_id, special_food_id, uses_remaining)
  values (auth.uid(), p_special_food_id, v_food.uses_per_purchase)
  returning * into v_inventory;

  return v_inventory;
end;
$$;
revoke all on function purchase_special_food(uuid) from public;
grant execute on function purchase_special_food(uuid) to authenticated;

-- Feed special food: consume one use, apply rewards, enforce cooldown.
create or replace function feed_special_food(p_inventory_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pet pets;
  v_inventory food_inventory;
  v_food special_foods;
  v_result json;
begin
  select * into v_pet from pets where user_id = auth.uid() for update;

  select * into v_inventory from food_inventory where id = p_inventory_id and user_id = auth.uid() for update;

  if v_inventory is null then
    raise exception 'inventory_not_found';
  end if;

  select * into v_food from special_foods where id = v_inventory.special_food_id;

  -- Check cooldown (per special food type)
  if v_pet.last_special_food_id = v_food.id
      and v_pet.last_special_fed_at is not null
      and v_pet.last_special_fed_at > now() - (v_food.satiation_hours || ' hours')::interval then
    raise exception 'feed_cooldown';
  end if;

  -- Check uses remaining
  if v_inventory.uses_remaining <= 0 then
    raise exception 'no_uses_remaining';
  end if;

  -- Consume one use
  update food_inventory
  set uses_remaining = uses_remaining - 1,
      last_used_at = now()
  where id = p_inventory_id;

  -- Apply rewards
  update pets
  set coins = coins + v_food.coin_reward,
      mood_score = least(mood_score + 15, 100),
      last_special_fed_at = now(),
      last_special_food_id = v_food.id,
      last_care_at = now()
  where user_id = auth.uid()
  returning * into v_pet;

  -- Delete inventory if exhausted
  delete from food_inventory where id = p_inventory_id and uses_remaining <= 0;

  select json_build_object(
    'pet', row_to_json(v_pet),
    'uses_remaining', v_inventory.uses_remaining - 1,
    'food', row_to_json(v_food)
  ) into v_result;

  return v_result;
end;
$$;
revoke all on function feed_special_food(uuid) from public;
grant execute on function feed_special_food(uuid) to authenticated;

-- Get user's available special foods with remaining uses.
create or replace function get_special_food_inventory()
returns table (
  id uuid,
  special_food_id uuid,
  key text,
  name text,
  uses_remaining integer,
  satiation_hours integer,
  coin_reward integer,
  bowl_asset text,
  last_used_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select fi.id,
         fi.special_food_id,
         sf.key,
         sf.name,
         fi.uses_remaining,
         sf.satiation_hours,
         sf.coin_reward,
         sf.bowl_asset,
         fi.last_used_at
  from food_inventory fi
  join special_foods sf on sf.id = fi.special_food_id
  where fi.user_id = auth.uid()
  order by fi.purchased_at desc;
end;
$$;
revoke all on function get_special_food_inventory() from public;
grant execute on function get_special_food_inventory() to authenticated;
