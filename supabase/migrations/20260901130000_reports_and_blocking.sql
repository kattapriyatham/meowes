-- User-generated-content safety (App Store 1.2 / Play UGC policy): let users
-- report objectionable content and block abusive people.
--
-- UGC surfaces in Meowes: expense descriptions, group names, pet names, and
-- "Remind" pings — all visible to other users, and invite links let anyone
-- become a friend instantly, so "known contacts only" is not a given.

-- ── Reports ──────────────────────────────────────────────────────────────
create table content_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references users(id) on delete cascade,
  target_type text not null check (target_type in ('expense', 'group', 'user', 'remind')),
  target_id uuid not null,
  reason text not null check (reason in ('offensive', 'harassment', 'spam', 'inappropriate', 'other')),
  details text,
  status text not null default 'open' check (status in ('open', 'reviewed', 'actioned', 'dismissed')),
  created_at timestamptz not null default now()
);

create index idx_content_reports_status on content_reports (status, created_at);

alter table content_reports enable row level security;

-- A user can file a report as themselves and see the ones they filed.
-- No update/delete for the authenticated role: the team triages via the
-- Supabase dashboard / a service-role tool.
create policy content_reports_insert_self on content_reports
  for insert to authenticated with check (reporter_id = auth.uid());
create policy content_reports_select_self on content_reports
  for select to authenticated using (reporter_id = auth.uid());

-- ── Blocking ─────────────────────────────────────────────────────────────
create table blocked_users (
  blocker_id uuid not null references users(id) on delete cascade,
  blocked_id uuid not null references users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

alter table blocked_users enable row level security;

create policy blocked_users_rw_self on blocked_users
  for all to authenticated
  using (blocker_id = auth.uid())
  with check (blocker_id = auth.uid());

-- Any friendship create/accept between a blocked pair is rejected, in either
-- direction. Covers the plain `friendships` insert (sendFriendRequest), the
-- accept UPDATE, and join_friendship_by_code's upsert.
create or replace function reject_blocked_friendship()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from blocked_users b
    where (b.blocker_id = new.user_id_a and b.blocked_id = new.user_id_b)
       or (b.blocker_id = new.user_id_b and b.blocked_id = new.user_id_a)
  ) then
    raise exception 'blocked';
  end if;
  return new;
end;
$$;

create trigger trg_reject_blocked_friendship
  before insert or update on friendships
  for each row execute function reject_blocked_friendship();

-- Block a user: record it, then tear down any existing friendship /
-- pending request between the two.
create or replace function block_user(p_target uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if p_target = v_uid then raise exception 'cannot_block_self'; end if;

  insert into blocked_users (blocker_id, blocked_id)
  values (v_uid, p_target)
  on conflict do nothing;

  delete from friendships
   where (user_id_a = least(v_uid, p_target) and user_id_b = greatest(v_uid, p_target));
end;
$$;

revoke all on function block_user(uuid) from public;
grant execute on function block_user(uuid) to authenticated;

-- send_friend_remind: also refuse if either side has blocked the other.
create or replace function send_friend_remind(p_friend_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_balance numeric;
  v_pet_name text;
begin
  if exists (
    select 1 from blocked_users b
    where (b.blocker_id = auth.uid() and b.blocked_id = p_friend_id)
       or (b.blocker_id = p_friend_id and b.blocked_id = auth.uid())
  ) then
    raise exception 'blocked';
  end if;

  -- Only allow if friend actually owes us
  select get_friend_balance(auth.uid(), p_friend_id) into v_balance;
  if v_balance <= 0.005 then
    raise exception 'no_positive_balance';
  end if;

  -- Get pet name for personalization
  select coalesce(name, 'Your cat') into v_pet_name
  from pets where user_id = auth.uid();

  perform net.http_post(
    url := 'https://pacbkvuepitmmqxudscx.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBhY2JrdnVlcGl0bW1xeHVkc2N4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODUxNTM4NjEsImV4cCI6MjEwMDcyOTg2MX0.UTgVDAD_dMtGVjANU5_Gssv9E9fnaJ0AP22-h4x8leE'
    ),
    body := jsonb_build_object(
      'type', 'friend_remind',
      'user_id', p_friend_id,
      'reminder_user_id', auth.uid(),
      'amount', v_balance,
      'pet_name', v_pet_name
    )
  );
end;
$$;
revoke all on function send_friend_remind(uuid) from public;
grant execute on function send_friend_remind(uuid) to authenticated;
