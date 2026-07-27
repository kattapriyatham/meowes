-- The original get_friend_balance had both settlement terms' signs
-- backwards; a fix pass changed only one, which happened to make the
-- plan's original single-direction test pass while leaving the other
-- settlement direction (user_a paying user_b) still computed backwards.
-- Correct signs: a confirmed settlement FROM a TO b means a gave b money,
-- which should ADD to "b owes a" (settled_a_to_b, +); a confirmed
-- settlement FROM b TO a should SUBTRACT from it (settled_b_to_a, -).
create or replace function get_friend_balance(user_a uuid, user_b uuid)
returns numeric
language plpgsql
stable
as $$
begin
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
