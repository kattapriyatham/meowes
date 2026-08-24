-- Feeding fish was locking treats/dry food too for the same 6h, since
-- the cooldown gate checked one shared last_fed_at/last_fed_food_key
-- regardless of which food is being fed next. Per user request, each
-- food type now tracks its own last-fed time and cools down
-- independently — feeding fish no longer touches treats' or dry food's
-- own clocks.
--
-- last_fed_at/last_fed_food_key are kept exactly as before: they still
-- drive hunger decay (apply_mood_decay) and the pet-hungry push
-- notification (check_hungry_pets), which reasonably stay "time since
-- any last meal" rather than needing a three-way hunger model.
alter table pets add column last_fish_fed_at timestamptz;
alter table pets add column last_treats_fed_at timestamptz;
alter table pets add column last_dry_food_fed_at timestamptz;

create or replace function feed_pet(p_food_key text default 'dry_food')
returns pets
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pet pets;
  v_today date := current_date;
  v_streak integer;
  v_bonus integer;
  v_base_reward integer;
  v_cooldown_hours integer;
  v_last_fed_this_food timestamptz;
begin
  perform get_or_create_pet();

  select * into v_pet from pets where user_id = auth.uid() for update;

  v_cooldown_hours := food_satiation_hours(p_food_key);
  v_last_fed_this_food := case p_food_key
    when 'fish' then v_pet.last_fish_fed_at
    when 'treats' then v_pet.last_treats_fed_at
    when 'dry_food' then v_pet.last_dry_food_fed_at
    else null
  end;

  if v_last_fed_this_food is not null
      and v_last_fed_this_food > now() - (v_cooldown_hours || ' hours')::interval then
    raise exception 'feed_cooldown';
  end if;

  v_base_reward := case p_food_key
    when 'fish' then 3
    when 'treats' then 2
    when 'dry_food' then 2
    else 2
  end;

  if v_pet.last_feed_streak_date = v_today - 1 then
    v_streak := v_pet.feed_streak_days + 1;
  elsif v_pet.last_feed_streak_date = v_today then
    v_streak := v_pet.feed_streak_days;
  else
    v_streak := 1;
  end if;

  v_bonus := case when v_streak = 7 then 10 else 0 end;

  update pets
  set coins = coins + v_base_reward + v_bonus,
      mood_score = least(mood_score + 10, 100),
      last_fed_at = now(),
      last_fed_food_key = p_food_key,
      last_fish_fed_at = case when p_food_key = 'fish' then now() else last_fish_fed_at end,
      last_treats_fed_at = case when p_food_key = 'treats' then now() else last_treats_fed_at end,
      last_dry_food_fed_at = case when p_food_key = 'dry_food' then now() else last_dry_food_fed_at end,
      last_hunger_decay_at = now(),
      hungry_notified = false,
      last_care_at = now(),
      feed_streak_days = case when v_streak = 7 then 0 else v_streak end,
      last_feed_streak_date = v_today
  where user_id = auth.uid()
  returning * into v_pet;

  return v_pet;
end;
$$;
revoke all on function feed_pet(text) from public;
grant execute on function feed_pet(text) to authenticated;
