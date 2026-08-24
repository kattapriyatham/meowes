-- Real push notifications (Android first via FCM; iOS follow-up once an
-- Apple Developer account + APNs key exist). Two independently-triggered
-- events call a `send-push` Edge Function via pg_net (async HTTP from
-- Postgres, doesn't block the triggering transaction):
--   1. expense_splits insert for someone who isn't the payer.
--   2. a pet's satiation window expiring (checked on a pg_cron schedule,
--      since "time has passed" isn't a row event anything can trigger on).
--
-- The Edge Function re-fetches the real expense/pet data itself using the
-- service-role key rather than trusting whatever a caller sends — the
-- anon key embedded below only proves "this call came from our own DB
-- trigger", it grants no elevated access, so there's nothing sensitive
-- being hardcoded.
create extension if not exists pg_net;
create extension if not exists pg_cron;

create table device_tokens (
  token text primary key,
  user_id uuid not null references users(id) on delete cascade,
  platform text not null check (platform in ('android', 'ios')),
  updated_at timestamptz not null default now()
);
create index idx_device_tokens_user on device_tokens(user_id);

alter table device_tokens enable row level security;

create policy device_tokens_select_owner on device_tokens
  for select to authenticated using (auth.uid() = user_id);
create policy device_tokens_delete_owner on device_tokens
  for delete to authenticated using (auth.uid() = user_id);

-- Registration goes through this RPC rather than a plain client upsert:
-- the same physical device can be reused across accounts (sign out, sign
-- in as someone else), and plain RLS can't reassign a token's ownership —
-- the UPDATE policy's USING clause would check the *old* user_id against
-- the *new* auth.uid() and always fail. SECURITY DEFINER sidesteps that,
-- same reasoning as join_group_by_code/join_friendship_by_code.
create or replace function register_device_token(p_token text, p_platform text)
returns void
language sql
security definer
set search_path = public
as $$
  insert into device_tokens (user_id, token, platform, updated_at)
  values (auth.uid(), p_token, p_platform, now())
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        updated_at = now();
$$;
revoke all on function register_device_token(text, text) from public;
grant execute on function register_device_token(text, text) to authenticated;

-- 1. Expense-involvement push: fires once per split row, only for the
-- people who didn't pay (the payer already knows).
create or replace function notify_expense_split()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_paid_by uuid;
begin
  select paid_by into v_paid_by from expenses where id = new.expense_id;
  if v_paid_by is distinct from new.user_id then
    perform net.http_post(
      url := 'https://pacbkvuepitmmqxudscx.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBhY2JrdnVlcGl0bW1xeHVkc2N4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODUxNTM4NjEsImV4cCI6MjEwMDcyOTg2MX0.UTgVDAD_dMtGVjANU5_Gssv9E9fnaJ0AP22-h4x8leE'
      ),
      body := jsonb_build_object('type', 'expense_split', 'expense_id', new.expense_id, 'user_id', new.user_id)
    );
  end if;
  return new;
end;
$$;

create trigger trg_notify_expense_split
after insert on expense_splits
for each row execute function notify_expense_split();

-- 2. Pet-hunger push: a pg_cron job checks every 15 minutes for pets past
-- their satiation window (food_satiation_hours(), from the feeding-TTL
-- work) that haven't already been notified for this hunger episode.
-- hungry_notified resets to false in feed_pet() on the next meal.
alter table pets add column hungry_notified boolean not null default false;

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
    where last_fed_at is not null
      and not hungry_notified
      and now() > last_fed_at + (food_satiation_hours(last_fed_food_key) || ' hours')::interval
  loop
    update pets set hungry_notified = true where user_id = r.user_id;
    perform net.http_post(
      url := 'https://pacbkvuepitmmqxudscx.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBhY2JrdnVlcGl0bW1xeHVkc2N4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODUxNTM4NjEsImV4cCI6MjEwMDcyOTg2MX0.UTgVDAD_dMtGVjANU5_Gssv9E9fnaJ0AP22-h4x8leE'
      ),
      body := jsonb_build_object('type', 'pet_hungry', 'user_id', r.user_id)
    );
  end loop;
end;
$$;
revoke all on function check_hungry_pets() from public;

select cron.schedule('check-hungry-pets', '*/15 * * * *', 'select check_hungry_pets()');

-- feed_pet() now clears hungry_notified so the next hunger episode can
-- notify again.
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
