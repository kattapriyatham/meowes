-- Applies mood decay lazily: -15 mood per full 24h elapsed since last_care_at.
create or replace function apply_mood_decay(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_days_elapsed integer;
begin
  select floor(extract(epoch from (now() - last_care_at)) / 86400)::int
    into v_days_elapsed
    from pets where user_id = p_user_id;

  if v_days_elapsed is not null and v_days_elapsed >= 1 then
    update pets
    set mood_score = greatest(mood_score - (15 * v_days_elapsed), 0),
        last_care_at = last_care_at + (v_days_elapsed || ' days')::interval
    where user_id = p_user_id;
  end if;
end;
$$;
revoke all on function apply_mood_decay(uuid) from public;

create or replace function get_or_create_pet()
returns pets
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pet pets;
begin
  select * into v_pet from pets where user_id = auth.uid();
  if not found then
    insert into pets (user_id) values (auth.uid()) returning * into v_pet;
    return v_pet;
  end if;
  perform apply_mood_decay(auth.uid());
  select * into v_pet from pets where user_id = auth.uid();
  return v_pet;
end;
$$;
revoke all on function get_or_create_pet() from public;
grant execute on function get_or_create_pet() to authenticated;

create or replace function feed_pet()
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
begin
  perform get_or_create_pet();

  select * into v_pet from pets where user_id = auth.uid() for update;

  if v_pet.last_fed_at is not null and v_pet.last_fed_at > now() - interval '3 hours' then
    raise exception 'feed_cooldown';
  end if;

  if v_pet.last_feed_streak_date = v_today - 1 then
    v_streak := v_pet.feed_streak_days + 1;
  elsif v_pet.last_feed_streak_date = v_today then
    v_streak := v_pet.feed_streak_days;
  else
    v_streak := 1;
  end if;

  v_bonus := case when v_streak = 7 then 10 else 0 end;

  update pets
  set coins = coins + 2 + v_bonus,
      mood_score = least(mood_score + 10, 100),
      last_fed_at = now(),
      last_care_at = now(),
      feed_streak_days = case when v_streak = 7 then 0 else v_streak end,
      last_feed_streak_date = v_today
  where user_id = auth.uid()
  returning * into v_pet;

  return v_pet;
end;
$$;
revoke all on function feed_pet() from public;
grant execute on function feed_pet() to authenticated;

create or replace function pet_the_cat()
returns pets
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pet pets;
begin
  perform get_or_create_pet();

  update pets
  set mood_score = least(mood_score + 10, 100),
      last_care_at = now()
  where user_id = auth.uid()
  returning * into v_pet;

  return v_pet;
end;
$$;
revoke all on function pet_the_cat() from public;
grant execute on function pet_the_cat() to authenticated;

create or replace function daily_check_in()
returns pets
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pet pets;
begin
  perform get_or_create_pet();

  select * into v_pet from pets where user_id = auth.uid() for update;

  if v_pet.last_checkin_at = current_date then
    raise exception 'already_checked_in';
  end if;

  update pets
  set coins = coins + 5,
      last_checkin_at = current_date
  where user_id = auth.uid()
  returning * into v_pet;

  return v_pet;
end;
$$;
revoke all on function daily_check_in() from public;
grant execute on function daily_check_in() to authenticated;

-- Deterministic per-user-per-day rotation: same 4 activities all day for
-- one user, different set for a different user or a different day.
create or replace function get_todays_activities()
returns setof activities
language sql
stable
security definer
set search_path = public
as $$
  select * from activities
  order by md5(auth.uid()::text || current_date::text || id::text)
  limit 4;
$$;
revoke all on function get_todays_activities() from public;
grant execute on function get_todays_activities() to authenticated;

create or replace function redeem_activity(p_activity_id uuid)
returns pet_memories
language plpgsql
security definer
set search_path = public
as $$
declare
  v_activity activities;
  v_pet pets;
  v_memory pet_memories;
begin
  select * into v_activity from activities where id = p_activity_id;
  if not found then
    raise exception 'activity_not_found';
  end if;

  perform get_or_create_pet();

  select * into v_pet from pets where user_id = auth.uid() for update;

  if v_pet.coins < v_activity.coin_cost then
    raise exception 'insufficient_coins';
  end if;

  update pets set coins = coins - v_activity.coin_cost where user_id = auth.uid();

  insert into pet_memories (user_id, activity_id, activity_name, caption, image_asset, coins_spent)
  values (auth.uid(), v_activity.id, v_activity.name, v_activity.caption, v_activity.image_asset, v_activity.coin_cost)
  returning * into v_memory;

  return v_memory;
end;
$$;
revoke all on function redeem_activity(uuid) from public;
grant execute on function redeem_activity(uuid) to authenticated;
