-- Reverses the "single hunger model" call in
-- 20260815160000_independent_food_cooldowns.sql: each food type now
-- tracks its own hungry_notified state and fires its own push
-- independently, since each already has its own cooldown clock
-- (last_fish_fed_at/last_treats_fed_at/last_dry_food_fed_at). A pet can
-- fire 0-3 pushes in one cron pass now, one per food that's due.
alter table pets add column hungry_notified_fish boolean not null default false;
alter table pets add column hungry_notified_treats boolean not null default false;
alter table pets add column hungry_notified_dry_food boolean not null default false;

create or replace function check_hungry_pets()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
begin
  for r in
    select user_id
    from pets
    where last_fish_fed_at is not null
      and not hungry_notified_fish
      and now() > last_fish_fed_at + (food_satiation_hours('fish') || ' hours')::interval
  loop
    update pets set hungry_notified_fish = true where user_id = r.user_id;
    perform net.http_post(
      url := 'https://pacbkvuepitmmqxudscx.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBhY2JrdnVlcGl0bW1xeHVkc2N4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODUxNTM4NjEsImV4cCI6MjEwMDcyOTg2MX0.UTgVDAD_dMtGVjANU5_Gssv9E9fnaJ0AP22-h4x8leE'
      ),
      body := jsonb_build_object('type', 'pet_hungry', 'user_id', r.user_id, 'food_key', 'fish')
    );
  end loop;

  for r in
    select user_id
    from pets
    where last_treats_fed_at is not null
      and not hungry_notified_treats
      and now() > last_treats_fed_at + (food_satiation_hours('treats') || ' hours')::interval
  loop
    update pets set hungry_notified_treats = true where user_id = r.user_id;
    perform net.http_post(
      url := 'https://pacbkvuepitmmqxudscx.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBhY2JrdnVlcGl0bW1xeHVkc2N4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODUxNTM4NjEsImV4cCI6MjEwMDcyOTg2MX0.UTgVDAD_dMtGVjANU5_Gssv9E9fnaJ0AP22-h4x8leE'
      ),
      body := jsonb_build_object('type', 'pet_hungry', 'user_id', r.user_id, 'food_key', 'treats')
    );
  end loop;

  for r in
    select user_id
    from pets
    where last_dry_food_fed_at is not null
      and not hungry_notified_dry_food
      and now() > last_dry_food_fed_at + (food_satiation_hours('dry_food') || ' hours')::interval
  loop
    update pets set hungry_notified_dry_food = true where user_id = r.user_id;
    perform net.http_post(
      url := 'https://pacbkvuepitmmqxudscx.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBhY2JrdnVlcGl0bW1xeHVkc2N4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODUxNTM4NjEsImV4cCI6MjEwMDcyOTg2MX0.UTgVDAD_dMtGVjANU5_Gssv9E9fnaJ0AP22-h4x8leE'
      ),
      body := jsonb_build_object('type', 'pet_hungry', 'user_id', r.user_id, 'food_key', 'dry_food')
    );
  end loop;
end;
$$;
revoke all on function check_hungry_pets() from public;

-- feed_pet() is unchanged except for how it clears hunger-notified state:
-- only the food actually fed gets its flag cleared, the other two foods'
-- notified state is untouched (each food's hunger is independent now).
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
      hungry_notified_fish = case when p_food_key = 'fish' then false else hungry_notified_fish end,
      hungry_notified_treats = case when p_food_key = 'treats' then false else hungry_notified_treats end,
      hungry_notified_dry_food = case when p_food_key = 'dry_food' then false else hungry_notified_dry_food end,
      last_care_at = now(),
      feed_streak_days = case when v_streak = 7 then 0 else v_streak end,
      last_feed_streak_date = v_today
  where user_id = auth.uid()
  returning * into v_pet;

  if v_streak = 7 then
    perform net.http_post(
      url := 'https://pacbkvuepitmmqxudscx.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBhY2JrdnVlcGl0bW1xeHVkc2N4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODUxNTM4NjEsImV4cCI6MjEwMDcyOTg2MX0.UTgVDAD_dMtGVjANU5_Gssv9E9fnaJ0AP22-h4x8leE'
      ),
      body := jsonb_build_object('type', 'streak_milestone', 'user_id', auth.uid(), 'streak_days', 7)
    );
  end if;

  return v_pet;
end;
$$;
revoke all on function feed_pet(text) from public;
grant execute on function feed_pet(text) to authenticated;

-- The old single-hunger-model column is fully superseded by the three
-- above; drop it last (function bodies above no longer reference it).
alter table pets drop column hungry_notified;
