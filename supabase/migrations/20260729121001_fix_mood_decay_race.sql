-- Fix race condition in apply_mood_decay: replace read-then-update with atomic UPDATE
-- Previous implementation had a window where concurrent calls could both read stale
-- last_care_at, then both UPDATE with the same v_days_elapsed, causing double decay.
-- New implementation computes decay from the same row snapshot in one atomic UPDATE.
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
end;
$$;
revoke all on function apply_mood_decay(uuid) from public;
