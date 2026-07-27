create or replace function get_friend_balance(user_a uuid, user_b uuid)
returns numeric
language plpgsql
stable
as $$
begin
  -- auth.uid() is null for the service/test context (test scripts, migrations);
  -- for any real authenticated call, only a party to the pair may query it.
  if auth.uid() is not null and auth.uid() not in (user_a, user_b) then
    raise exception 'not authorized to view this balance';
  end if;

  return (with paid_by_a as (
    select coalesce(sum(es.share_amount), 0) as amt
    from expense_splits es
    join expenses e on e.id = es.expense_id
    where e.deleted_at is null
      and e.paid_by = user_a
      and es.user_id = user_b
  ),
  paid_by_b as (
    select coalesce(sum(es.share_amount), 0) as amt
    from expense_splits es
    join expenses e on e.id = es.expense_id
    where e.deleted_at is null
      and e.paid_by = user_b
      and es.user_id = user_a
  ),
  settled_a_to_b as (
    select coalesce(sum(amount), 0) as amt
    from settlements
    where status = 'confirmed' and from_user = user_a and to_user = user_b
  ),
  settled_b_to_a as (
    select coalesce(sum(amount), 0) as amt
    from settlements
    where status = 'confirmed' and from_user = user_b and to_user = user_a
  )
  select (select amt from paid_by_a)
       - (select amt from paid_by_b)
       + (select amt from settled_a_to_b)
       - (select amt from settled_b_to_a));
end;
$$;

create or replace function get_group_debts(target_group_id uuid)
returns table(from_user uuid, to_user uuid, amount numeric)
language plpgsql
volatile
as $$
declare
  net_balances jsonb;
  creditors record;
  debtors record;
  creditor_list uuid[];
  creditor_amounts numeric[];
  debtor_list uuid[];
  debtor_amounts numeric[];
  ci int := 1;
  di int := 1;
  settle_amount numeric;
begin
  -- auth.uid() is null for the service/test context (test scripts, migrations);
  -- for any real authenticated call, only an actual member of the group
  -- may query its debts.
  if auth.uid() is not null and not exists (
    select 1 from group_members gm where gm.group_id = target_group_id and gm.user_id = auth.uid()
  ) then
    raise exception 'not authorized to view this group''s debts';
  end if;

  -- Net balance per member: positive = owed money, negative = owes money.
  create temporary table if not exists _member_net on commit drop as
  select gm.user_id,
    coalesce(sum(case when e.paid_by = gm.user_id then es.share_amount_total - es.own_share else 0 end), 0)
    - coalesce(sum(case when e.paid_by != gm.user_id then es.own_share_paid_by_other else 0 end), 0)
    as net
  from group_members gm
  left join lateral (
    select e2.id as expense_id, e2.paid_by,
      (select sum(es2.share_amount) from expense_splits es2 where es2.expense_id = e2.id) as share_amount_total,
      (select coalesce(es3.share_amount, 0) from expense_splits es3 where es3.expense_id = e2.id and es3.user_id = gm.user_id) as own_share,
      (select coalesce(es4.share_amount, 0) from expense_splits es4 where es4.expense_id = e2.id and es4.user_id = gm.user_id) as own_share_paid_by_other
    from expenses e2
    where e2.group_id = target_group_id and e2.deleted_at is null
  ) es on true
  left join expenses e on e.id = es.expense_id
  where gm.group_id = target_group_id
  group by gm.user_id;

  -- Apply confirmed settlements within this group to the net balances. A
  -- settlement FROM this member means they paid down debt, moving their net
  -- toward positive (+); a settlement TO this member means they received a
  -- payment, reducing what they're owed, moving their net toward zero (-).
  update _member_net m
  set net = m.net + coalesce((
    select sum(s.amount) from settlements s
    where s.group_id = target_group_id and s.status = 'confirmed' and s.from_user = m.user_id
  ), 0) - coalesce((
    select sum(s.amount) from settlements s
    where s.group_id = target_group_id and s.status = 'confirmed' and s.to_user = m.user_id
  ), 0);

  -- Greedy min-transaction simplification.
  select array_agg(user_id order by net desc), array_agg(net order by net desc)
  into creditor_list, creditor_amounts
  from _member_net where net > 0.005;

  select array_agg(user_id order by net asc), array_agg(-net order by net asc)
  into debtor_list, debtor_amounts
  from _member_net where net < -0.005;

  if creditor_list is null or debtor_list is null then
    return;
  end if;

  while ci <= array_length(creditor_list, 1) and di <= array_length(debtor_list, 1) loop
    settle_amount := least(creditor_amounts[ci], debtor_amounts[di]);
    from_user := debtor_list[di];
    to_user := creditor_list[ci];
    amount := round(settle_amount, 2);
    return next;

    creditor_amounts[ci] := creditor_amounts[ci] - settle_amount;
    debtor_amounts[di] := debtor_amounts[di] - settle_amount;

    if creditor_amounts[ci] <= 0.005 then ci := ci + 1; end if;
    if debtor_amounts[di] <= 0.005 then di := di + 1; end if;
  end loop;

  return;
end;
$$;
