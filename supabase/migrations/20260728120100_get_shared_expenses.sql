-- Direct (non-group) expenses between exactly two people can't be
-- expressed as a single-table filter the way group expenses can (need
-- "no group AND both people involved"), so this is a small RPC, same
-- pattern as the existing get_friend_balance.
--
-- Must be security definer, not security invoker: when other_user is the
-- payer (not auth.uid()), the exists check against
-- expense_splits.user_id = other_user runs on a non-group expense the
-- caller neither paid nor created, which expense_splits_select_participant
-- RLS would normally hide from them — an invoker-security function would
-- silently under-return real shared expenses in exactly that case.
-- Bypassing RLS here is safe because the query's own two exists clauses
-- already constrain every returned row to one where BOTH auth.uid() and
-- other_user have a split — a caller can never get back an expense they
-- weren't actually part of.
create or replace function get_shared_expenses(other_user uuid)
returns setof expenses
language sql
security definer
set search_path = public
stable
as $$
  select e.* from expenses e
  where e.deleted_at is null
    and e.group_id is null
    and (e.paid_by = auth.uid() or e.paid_by = other_user)
    and exists (
      select 1 from expense_splits es
      where es.expense_id = e.id and es.user_id = other_user
    )
    and exists (
      select 1 from expense_splits es
      where es.expense_id = e.id and es.user_id = auth.uid()
    );
$$;

revoke all on function get_shared_expenses(uuid) from public;
grant execute on function get_shared_expenses(uuid) to authenticated;
