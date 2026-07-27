-- get_group_debts' second statement (applying confirmed settlements onto
-- the temp per-member net balances) is an UPDATE with no WHERE clause:
--
--   update _member_net m
--   set net = m.net + coalesce(...) - coalesce(...);
--
-- This project's remote Postgres rejects any UPDATE lacking a WHERE clause
-- outright (confirmed via direct RPC call, both as service_role and as a
-- real authenticated user against a real group: "UPDATE requires a WHERE
-- clause", SQLSTATE 21000) — so every call to get_group_debts has been
-- failing, silently swallowed wherever the caller falls back to an empty
-- list on error (e.g. HomeScreen's group tiles, which then render as
-- "Settled" regardless of actual balance).
--
-- The row-scoping already happens inside the two correlated subqueries
-- (each keyed to m.user_id), so a trivial `where true` changes nothing
-- about the update's actual behavior — it only satisfies the guard.
create or replace function get_group_debts(target_group_id uuid)
returns table(from_user uuid, to_user uuid, amount numeric)
language plpgsql
volatile
as $$
declare
  creditor_list uuid[];
  creditor_amounts numeric[];
  debtor_list uuid[];
  debtor_amounts numeric[];
  ci int := 1;
  di int := 1;
  settle_amount numeric;
begin
  if auth.uid() is not null and not exists (
    select 1 from group_members gm where gm.group_id = target_group_id and gm.user_id = auth.uid()
  ) then
    raise exception 'not authorized to view this group''s debts';
  end if;

  drop table if exists _member_net;
  create temporary table _member_net on commit drop as
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

  update _member_net m
  set net = m.net + coalesce((
    select sum(s.amount) from settlements s
    where s.group_id = target_group_id and s.status = 'confirmed' and s.from_user = m.user_id
  ), 0) - coalesce((
    select sum(s.amount) from settlements s
    where s.group_id = target_group_id and s.status = 'confirmed' and s.to_user = m.user_id
  ), 0)
  where true;

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
