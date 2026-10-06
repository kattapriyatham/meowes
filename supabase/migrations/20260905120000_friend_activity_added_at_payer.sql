-- Friend Detail activity rows now carry added_at (when it was added) and
-- paid_by_me (who paid) so the UI can show a timestamp and payer per row.
-- Return type changes, so the old function must be dropped first.
drop function if exists get_friend_activity(uuid);

create or replace function get_friend_activity(other_user uuid)
returns table(
  kind text, ref_id uuid, name text, net numeric, activity_date date,
  -- Exact moment the row was added (expense created_at, settlement confirmation,
  -- or the latest such event inside a group).
  added_at timestamptz,
  -- True when the signed-in user paid; false when the friend paid; null for
  -- aggregated group rows, which have no single payer.
  paid_by_me boolean
)
language sql
security definer
set search_path = public
stable
as $$
  -- 1. Direct (non-group) expenses, one row each.
  select 'expense'::text as kind,
         e.id as ref_id,
         e.description as name,
         (
           (case when e.paid_by = auth.uid() then coalesce(
              (select es.share_amount from expense_splits es
               where es.expense_id = e.id and es.user_id = other_user), 0) else 0 end)
         - (case when e.paid_by = other_user then coalesce(
              (select es.share_amount from expense_splits es
               where es.expense_id = e.id and es.user_id = auth.uid()), 0) else 0 end)
         )::numeric as net,
         e.expense_date as activity_date,
         e.created_at as added_at,
         (e.paid_by = auth.uid()) as paid_by_me
  from expenses e
  where e.deleted_at is null
    and e.group_id is null
    and (
      (e.paid_by = auth.uid() and exists (
         select 1 from expense_splits es where es.expense_id = e.id and es.user_id = other_user))
      or
      (e.paid_by = other_user and exists (
         select 1 from expense_splits es where es.expense_id = e.id and es.user_id = auth.uid()))
    )

  union all

  -- 2. Shared groups (both are members), one aggregated row each.
  select 'group'::text as kind,
         g.id as ref_id,
         g.name as name,
         (
           coalesce((
             select sum(
               (case when e.paid_by = auth.uid() then coalesce(
                  (select es.share_amount from expense_splits es
                   where es.expense_id = e.id and es.user_id = other_user), 0) else 0 end)
             - (case when e.paid_by = other_user then coalesce(
                  (select es.share_amount from expense_splits es
                   where es.expense_id = e.id and es.user_id = auth.uid()), 0) else 0 end)
             )
             from expenses e
             where e.group_id = g.id and e.deleted_at is null
           ), 0)
           + coalesce((
             select sum(case when s.from_user = auth.uid() then s.amount
                             when s.from_user = other_user then -s.amount
                             else 0 end)
             from settlements s
             where s.group_id = g.id and s.status = 'confirmed'
               and ((s.from_user = auth.uid() and s.to_user = other_user)
                 or (s.from_user = other_user and s.to_user = auth.uid()))
           ), 0)
         )::numeric as net,
         greatest(
           coalesce((select max(e.expense_date) from expenses e
                     where e.group_id = g.id and e.deleted_at is null), 'epoch'::date),
           coalesce((select max(coalesce(s.confirmed_at::date, s.created_at::date))
                     from settlements s
                     where s.group_id = g.id and s.status = 'confirmed'
                       and ((s.from_user = auth.uid() and s.to_user = other_user)
                         or (s.from_user = other_user and s.to_user = auth.uid()))),
                    'epoch'::date)
         ) as activity_date,
         coalesce(
           greatest(
             (select max(e.created_at) from expenses e
              where e.group_id = g.id and e.deleted_at is null),
             (select max(coalesce(s.confirmed_at, s.created_at))
              from settlements s
              where s.group_id = g.id and s.status = 'confirmed'
                and ((s.from_user = auth.uid() and s.to_user = other_user)
                  or (s.from_user = other_user and s.to_user = auth.uid())))
           ),
           g.created_at
         ) as added_at,
         null::boolean as paid_by_me
  from groups g
  where exists (select 1 from group_members gm where gm.group_id = g.id and gm.user_id = auth.uid())
    and exists (select 1 from group_members gm where gm.group_id = g.id and gm.user_id = other_user)

  union all

  -- 3. Direct (non-group) confirmed settlements between the pair, one row each.
  select 'settlement'::text as kind,
         s.id as ref_id,
         'Payment'::text as name,
         (case when s.from_user = auth.uid() then s.amount else -s.amount end)::numeric as net,
         coalesce(s.confirmed_at::date, s.created_at::date) as activity_date,
         coalesce(s.confirmed_at, s.created_at) as added_at,
         (s.from_user = auth.uid()) as paid_by_me
  from settlements s
  where s.group_id is null
    and s.status = 'confirmed'
    and ((s.from_user = auth.uid() and s.to_user = other_user)
      or (s.from_user = other_user and s.to_user = auth.uid()));
$$;

revoke all on function get_friend_activity(uuid) from public;
grant execute on function get_friend_activity(uuid) to authenticated;
