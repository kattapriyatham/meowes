-- Friend Detail's activity list. Decomposes the exact math of
-- get_friend_balance(me, friend) into displayable rows so the list
-- reconciles to the header balance:
--   * direct expenses (group_id is null)  -> one row each
--   * shared groups (both are members)    -> one aggregated row each
--   * direct settlements (group_id null)  -> one row each ("Payment")
-- Sign convention matches get_friend_balance: net > 0 => friend owes me,
-- net < 0 => I owe the friend.
--
-- SECURITY DEFINER: reads splits, group names, memberships and
-- settlements that RLS may hide from the caller when the counterparty is
-- the payer/creator. Safe because every row is constrained to the
-- me(auth.uid())<->other_user relationship, so a caller only ever sees
-- their own activity.
create or replace function get_friend_activity(other_user uuid)
returns table(kind text, ref_id uuid, name text, net numeric, activity_date date)
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
         e.expense_date as activity_date
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
         ) as activity_date
  from groups g
  where exists (select 1 from group_members gm where gm.group_id = g.id and gm.user_id = auth.uid())
    and exists (select 1 from group_members gm where gm.group_id = g.id and gm.user_id = other_user)

  union all

  -- 3. Direct (non-group) confirmed settlements between the pair, one row each.
  select 'settlement'::text as kind,
         s.id as ref_id,
         'Payment'::text as name,
         (case when s.from_user = auth.uid() then s.amount else -s.amount end)::numeric as net,
         coalesce(s.confirmed_at::date, s.created_at::date) as activity_date
  from settlements s
  where s.group_id is null
    and s.status = 'confirmed'
    and ((s.from_user = auth.uid() and s.to_user = other_user)
      or (s.from_user = other_user and s.to_user = auth.uid()));
$$;

revoke all on function get_friend_activity(uuid) from public;
grant execute on function get_friend_activity(uuid) to authenticated;
