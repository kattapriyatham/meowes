-- Friend remind notification: send push when user reminds friend they owe money.
-- Positive balance from get_friend_balance(me, friend) means friend owes me.

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