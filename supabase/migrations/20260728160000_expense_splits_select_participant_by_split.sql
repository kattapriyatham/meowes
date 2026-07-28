-- expense_splits_select_participant let a caller read a split only when it
-- was their own row, or they owned the expense (payer/creator), or it was a
-- group expense they belong to. For a DIRECT (non-group) expense the other
-- person paid, a participant could therefore see only their own split row —
-- never the counterparty's — so ExpenseDetailScreen showed an incomplete
-- "Split between" for any direct expense you didn't pay.
--
-- The expenses_select_participant policy already grants visibility to anyone
-- who has_expense_split on the row; mirror that here so any participant of an
-- expense can see all of its splits. Safe: has_expense_split is SECURITY
-- DEFINER and only returns true when the caller genuinely has a split on that
-- expense, so it never widens visibility beyond expenses the caller is part of.
drop policy if exists expense_splits_select_participant on expense_splits;
create policy expense_splits_select_participant on expense_splits
  for select to authenticated using (
    user_id = auth.uid()
    or has_expense_split(expense_id, auth.uid())
    or is_expense_owner_or_group_member(expense_id, auth.uid())
  );
