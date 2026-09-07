-- Unified activity feed: everything that's happened to the signed-in user
-- across expenses, settlements, and pet-coin spending, one chronological
-- list instead of three separate per-domain queries. Mirrors
-- get_friend_activity()'s shape but app-wide rather than scoped to one
-- friend, and without that function's net-balance math (a feed just needs
-- "what happened", not "who owes what").
--
-- No SECURITY DEFINER: every row this touches (expenses I paid/split,
-- confirmed settlements I'm party to, my own pet_memories) is already
-- visible to the caller under existing RLS, so this runs as the caller
-- (security invoker, the default) rather than bypassing RLS.
create or replace function get_my_activity_feed()
returns table(
  kind text,
  ref_id uuid,
  title text,
  counterpart_id uuid,
  amount numeric,
  -- True when the signed-in user is the one who paid: the expense's payer,
  -- or the settlement's from_user. Without this the client can't tell "You
  -- paid X" from "X paid you" from counterpart_id alone, since that column
  -- holds "whichever side isn't me" either way. Unused for pet_activity.
  is_mine boolean,
  occurred_at timestamptz
)
language sql
stable
set search_path = public
as $$
  -- 1. Expenses I paid or am split into (direct or group), not deleted.
  select 'expense'::text as kind,
         e.id as ref_id,
         e.description as title,
         e.paid_by as counterpart_id,
         e.amount as amount,
         (e.paid_by = auth.uid()) as is_mine,
         e.created_at as occurred_at
  from expenses e
  where e.deleted_at is null
    and (
      e.paid_by = auth.uid()
      or exists (select 1 from expense_splits es where es.expense_id = e.id and es.user_id = auth.uid())
    )

  union all

  -- 2. Settlements I'm party to, once confirmed by the payee.
  select 'settlement'::text as kind,
         s.id as ref_id,
         null::text as title,
         (case when s.from_user = auth.uid() then s.to_user else s.from_user end) as counterpart_id,
         s.amount as amount,
         (s.from_user = auth.uid()) as is_mine,
         coalesce(s.confirmed_at, s.created_at) as occurred_at
  from settlements s
  where s.status = 'confirmed'
    and (s.from_user = auth.uid() or s.to_user = auth.uid())

  union all

  -- 3. Pet activities redeemed with coins.
  select 'pet_activity'::text as kind,
         pm.id as ref_id,
         pm.activity_name as title,
         null::uuid as counterpart_id,
         pm.coins_spent::numeric as amount,
         null::boolean as is_mine,
         pm.completed_at as occurred_at
  from pet_memories pm
  where pm.user_id = auth.uid();
$$;
grant execute on function get_my_activity_feed() to authenticated;
