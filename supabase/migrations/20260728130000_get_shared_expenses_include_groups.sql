-- Friend Detail's expense history uses get_shared_expenses, while the
-- friend balance on Home (and Friend Detail's header) uses
-- get_friend_balance. The two disagreed: get_friend_balance sums pairwise
-- expense_splits across ALL expenses (it has no group filter), so a group
-- expense where the friend paid and I have a share DOES move the friend
-- balance — but the original get_shared_expenses restricted itself to
-- `group_id is null`, so those same group expenses never appeared in the
-- history. Result: a non-zero balance with an empty expense list.
--
-- Fix: drop the `group_id is null` restriction and make the row predicate
-- mirror get_friend_balance's two expense terms exactly, so every line
-- item shown is one that actually contributes to the pairwise balance:
--   - I paid and the friend has a split  (friend owes me their share), or
--   - the friend paid and I have a split  (I owe the friend my share).
-- Note this deliberately keys off the payer + the counterparty's split
-- (not "both have a split"): that's precisely the pair of terms
-- get_friend_balance sums, so history and balance stay consistent even
-- when the payer took no share of their own expense.
--
-- Still SECURITY DEFINER: when the friend is the payer, the split-exists
-- check reads a row (their split, or a group expense) that
-- expense_splits_select_participant / group RLS might hide from the
-- caller, which would silently under-return real shared expenses. Safe
-- because every returned row has the caller as either the payer or a
-- split participant, so a caller can never see an expense they weren't
-- part of.
create or replace function get_shared_expenses(other_user uuid)
returns setof expenses
language sql
security definer
set search_path = public
stable
as $$
  select e.* from expenses e
  where e.deleted_at is null
    and (
      (
        e.paid_by = auth.uid()
        and exists (
          select 1 from expense_splits es
          where es.expense_id = e.id and es.user_id = other_user
        )
      )
      or (
        e.paid_by = other_user
        and exists (
          select 1 from expense_splits es
          where es.expense_id = e.id and es.user_id = auth.uid()
        )
      )
    );
$$;

revoke all on function get_shared_expenses(uuid) from public;
grant execute on function get_shared_expenses(uuid) to authenticated;
