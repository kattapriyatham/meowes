-- Confirming a settlement now also credits the payer's pet coins,
-- atomically with the status transition, idempotent on double-confirm.
create or replace function confirm_settlement_and_award_coins(p_settlement_id uuid)
returns settlements
language plpgsql
security definer
set search_path = public
as $$
declare
  v_settlement settlements;
begin
  select * into v_settlement from settlements where id = p_settlement_id for update;

  if not found then
    raise exception 'settlement_not_found';
  end if;

  if v_settlement.to_user <> auth.uid() then
    raise exception 'not_authorized';
  end if;

  if v_settlement.status = 'confirmed' then
    return v_settlement;
  end if;

  update settlements
  set status = 'confirmed', confirmed_at = now()
  where id = p_settlement_id
  returning * into v_settlement;

  insert into pets (user_id) values (v_settlement.from_user)
    on conflict (user_id) do nothing;

  update pets set coins = coins + 20 where user_id = v_settlement.from_user;

  return v_settlement;
end;
$$;
revoke all on function confirm_settlement_and_award_coins(uuid) from public;
grant execute on function confirm_settlement_and_award_coins(uuid) to authenticated;
