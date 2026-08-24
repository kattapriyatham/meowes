-- Replaces the flat 3-hour feed cooldown with a per-food satiation window
-- (Fish keeps a cat full longest, Treats shortest), and adds a hunger decay
-- so mood actually drops once that window runs out, instead of only
-- decaying on a fixed daily clock unrelated to feeding.
alter table pets add column last_fed_food_key text;
alter table pets add column last_hunger_decay_at timestamptz;

create or replace function food_satiation_hours(p_food_key text)
returns integer
language sql
immutable
as $$
  select case p_food_key
    when 'fish' then 6
    when 'dry_food' then 4
    when 'treats' then 12
    else 3
  end;
$$;

-- Extends the existing (race-safe, atomic-UPDATE) neglect decay with a
-- second atomic UPDATE for hunger: once now() passes the last meal's
-- satiation window, mood drops 3 points per additional full hour hungry.
-- last_hunger_decay_at tracks how far that decay has already been applied
-- so repeated calls within the same hour don't double-decay.
create or replace function apply_mood_decay(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update pets
  set mood_score = greatest(
        mood_score - 15 * floor(extract(epoch from (now() - last_care_at)) / 86400)::int,
        0
      ),
      last_care_at = last_care_at
        + (floor(extract(epoch from (now() - last_care_at)) / 86400)::int || ' days')::interval
  where user_id = p_user_id
    and floor(extract(epoch from (now() - last_care_at)) / 86400)::int >= 1;

  with raw as (
    select user_id,
           last_fed_at + (food_satiation_hours(last_fed_food_key) || ' hours')::interval as satiated_until,
           last_hunger_decay_at
    from pets
    where user_id = p_user_id and last_fed_at is not null
  ),
  baseline as (
    select user_id, greatest(satiated_until, coalesce(last_hunger_decay_at, satiated_until)) as baseline
    from raw
  ),
  hungry as (
    select user_id, baseline, floor(extract(epoch from (now() - baseline)) / 3600)::int as hours_hungry
    from baseline
  )
  update pets p
  set mood_score = greatest(p.mood_score - 3 * hungry.hours_hungry, 0),
      last_hunger_decay_at = hungry.baseline + (hungry.hours_hungry || ' hours')::interval
  from hungry
  where p.user_id = hungry.user_id and hungry.hours_hungry >= 1;
end;
$$;
revoke all on function apply_mood_decay(uuid) from public;

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
begin
  perform get_or_create_pet();

  select * into v_pet from pets where user_id = auth.uid() for update;

  v_cooldown_hours := food_satiation_hours(v_pet.last_fed_food_key);
  if v_pet.last_fed_at is not null and v_pet.last_fed_at > now() - (v_cooldown_hours || ' hours')::interval then
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
      last_hunger_decay_at = now(),
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
