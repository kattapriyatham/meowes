#!/usr/bin/env bash
# supabase/tests/database/run_balance_rpc_tests.sh
#
# Drives assertions against the linked cloud Supabase project directly —
# no Docker, no local Postgres. Each `supabase db query --linked` call is
# a fresh connection, so fixtures are set up via plain INSERTs (not a
# transaction held open across calls) and torn down at the end via a trap,
# making repeated runs idempotent.
set -euo pipefail

ALEX='11111111-1111-1111-1111-111111111111'
SAM='22222222-2222-2222-2222-222222222222'
EXPENSE1='33333333-3333-3333-3333-333333333333'
EXPENSE_SAM_PAID='77777777-7777-7777-7777-777777777777'
PRIYA='44444444-4444-4444-4444-444444444444'
TRIP_GROUP='55555555-5555-5555-5555-555555555555'
EXPENSE2='66666666-6666-6666-6666-666666666666'
EMPTY_GROUP='88888888-8888-8888-8888-888888888888'

pass_count=0
fail_count=0

cleanup() {
  supabase db query --linked "
    delete from settlements where group_id = '$TRIP_GROUP' or from_user in ('$ALEX','$SAM','$PRIYA') or to_user in ('$ALEX','$SAM','$PRIYA');
    delete from expense_splits where expense_id in ('$EXPENSE1', '$EXPENSE_SAM_PAID');
    delete from expenses where id in ('$EXPENSE1', '$EXPENSE_SAM_PAID');
    delete from expense_splits where expense_id = '$EXPENSE2';
    delete from expenses where id = '$EXPENSE2';
    delete from group_members where group_id in ('$TRIP_GROUP', '$EMPTY_GROUP');
    delete from groups where id in ('$TRIP_GROUP', '$EMPTY_GROUP');
    delete from users where id in ('$ALEX','$SAM','$PRIYA');
    delete from auth.users where id in ('$ALEX','$SAM','$PRIYA');
  " > /dev/null 2>&1 || true
}

trap cleanup EXIT
cleanup  # idempotent pre-clean in case a previous run left fixtures behind

check() {
  local description="$1"
  local bool_expr="$2"
  local actual_expr="$3"
  local json
  json=$(supabase db query --linked --output-format json \
    "select ($bool_expr) as passed, ($actual_expr) as actual;" 2>/dev/null)
  local passed actual
  passed=$(echo "$json" | jq -r '.rows[0].passed')
  actual=$(echo "$json" | jq -r '.rows[0].actual')
  if [[ "$passed" == "true" ]]; then
    echo "ok - $description"
    pass_count=$((pass_count + 1))
  else
    echo "not ok - $description (actual: $actual)"
    fail_count=$((fail_count + 1))
  fi
}

supabase db query --linked "
  insert into auth.users (id) values ('$ALEX'), ('$SAM');
  insert into users (id, name) values ('$ALEX', 'Alex'), ('$SAM', 'Sam');
  insert into expenses (id, group_id, paid_by, description, amount, expense_date, created_by)
  values ('$EXPENSE1', null, '$ALEX', 'Dinner', 1000.00, current_date, '$ALEX');
  insert into expense_splits (expense_id, user_id, share_amount) values
    ('$EXPENSE1', '$ALEX', 500.00),
    ('$EXPENSE1', '$SAM', 500.00);
" > /dev/null

check "Sam owes Alex 500 before any settlement" \
  "get_friend_balance('$ALEX', '$SAM') = 500.00" \
  "get_friend_balance('$ALEX', '$SAM')"

supabase db query --linked "
  insert into settlements (group_id, from_user, to_user, amount, status, confirmed_at)
  values (null, '$SAM', '$ALEX', 500.00, 'confirmed', now());
" > /dev/null

check "Balance is zero after a confirmed settlement covers the debt" \
  "get_friend_balance('$ALEX', '$SAM') = 0.00" \
  "get_friend_balance('$ALEX', '$SAM')"

supabase db query --linked "
  insert into settlements (group_id, from_user, to_user, amount, status, confirmed_at)
  values (null, '$ALEX', '$SAM', 200.00, 'confirmed', now());
" > /dev/null

check "Balance flips when the settlement direction reverses (Alex pays Sam 200 with no expense behind it, so Sam now owes Alex 200)" \
  "get_friend_balance('$ALEX', '$SAM') = 200.00" \
  "get_friend_balance('$ALEX', '$SAM')"

supabase db query --linked "
  insert into expenses (id, group_id, paid_by, description, amount, expense_date, created_by)
  values ('$EXPENSE_SAM_PAID', null, '$SAM', 'Groceries', 300.00, current_date, '$SAM');
  insert into expense_splits (expense_id, user_id, share_amount) values
    ('$EXPENSE_SAM_PAID', '$ALEX', 150.00),
    ('$EXPENSE_SAM_PAID', '$SAM', 150.00);
" > /dev/null

check "paid_by_b term reduces the balance correctly (Sam pays for groceries, Alex owes his 150 share, netting the current 200 down to 50)" \
  "get_friend_balance('$ALEX', '$SAM') = 50.00" \
  "get_friend_balance('$ALEX', '$SAM')"

supabase db query --linked "
  insert into auth.users (id) values ('$PRIYA');
  insert into users (id, name) values ('$PRIYA', 'Priya');
  insert into groups (id, name, created_by) values ('$TRIP_GROUP', 'Trip', '$ALEX');
  insert into group_members (group_id, user_id) values
    ('$TRIP_GROUP', '$ALEX'),
    ('$TRIP_GROUP', '$SAM'),
    ('$TRIP_GROUP', '$PRIYA');
  insert into expenses (id, group_id, paid_by, description, amount, expense_date, created_by)
  values ('$EXPENSE2', '$TRIP_GROUP', '$ALEX', 'Cabin', 300.00, current_date, '$ALEX');
  insert into expense_splits (expense_id, user_id, share_amount) values
    ('$EXPENSE2', '$ALEX', 100.00),
    ('$EXPENSE2', '$SAM', 100.00),
    ('$EXPENSE2', '$PRIYA', 100.00);
" > /dev/null

check "Two simplified transactions settle a three-person group" \
  "(select count(*)::int from get_group_debts('$TRIP_GROUP')) = 2" \
  "(select count(*)::int from get_group_debts('$TRIP_GROUP'))"

supabase db query --linked "
  insert into settlements (group_id, from_user, to_user, amount, status, confirmed_at)
  values ('$TRIP_GROUP', '$SAM', '$ALEX', 100.00, 'confirmed', now());
" > /dev/null

check "A confirmed group settlement removes that debtor from the simplified list, leaving only Priya owing Alex 100" \
  "(select count(*) from get_group_debts('$TRIP_GROUP') where from_user = '$PRIYA' and to_user = '$ALEX' and amount = 100.00) = 1 and (select count(*) from get_group_debts('$TRIP_GROUP')) = 1" \
  "(select array_agg(row(from_user, to_user, amount)) from get_group_debts('$TRIP_GROUP'))"

# Regression test for RLS recursion: every check above runs as the
# superuser/service role (via `supabase db query`), which bypasses RLS
# entirely and would not have caught the "infinite recursion detected in
# policy for relation ..." errors found in review — those only surface
# under the real `authenticated` role with a real auth.uid(). This check
# simulates that by setting `role authenticated` plus a JWT sub claim
# before calling get_group_debts, which internally reads group_members,
# expenses, and expense_splits — the exact tables whose cross-referencing
# SELECT policies previously recursed into each other.
rls_json=$(supabase db query --linked --output-format json "
  set local role authenticated;
  set local request.jwt.claim.sub = '$ALEX';
  select (select count(*) from get_group_debts('$TRIP_GROUP') where from_user = '$PRIYA' and to_user = '$ALEX' and amount = 100.00) = 1 as passed;
" 2>/dev/null)
rls_passed=$(echo "$rls_json" | jq -r '.rows[0].passed // "false"')
if [[ "$rls_passed" == "true" ]]; then
  echo "ok - get_group_debts works under real authenticated-role RLS (no policy recursion)"
  pass_count=$((pass_count + 1))
else
  echo "not ok - get_group_debts under real authenticated-role RLS ($rls_json)"
  fail_count=$((fail_count + 1))
fi

supabase db query --linked "
  insert into groups (id, name, created_by) values ('$EMPTY_GROUP', 'Empty', '$ALEX');
  insert into group_members (group_id, user_id) values ('$EMPTY_GROUP', '$ALEX');
" > /dev/null

# Regression test for the temp-table reuse bug found in review: calling
# get_group_debts for two different groups in one statement/transaction
# must not leak the first group's debts into the second's (unrelated,
# expense-less) result.
check "Querying a second, unrelated empty group in the same call returns no debts (no cross-group leakage from the prior TRIP_GROUP call)" \
  "(select count(*) from get_group_debts('$TRIP_GROUP')) = 1 and (select count(*) from get_group_debts('$EMPTY_GROUP')) = 0" \
  "(select count(*) from get_group_debts('$EMPTY_GROUP'))"

# get_shared_expenses must line up with get_friend_balance: any expense
# that moves the pairwise balance should appear in the friend's history.
# It reads auth.uid(), so (like the RLS test above) it must run under the
# authenticated role with a JWT sub claim — the service role used by
# check() has a null auth.uid() and would return nothing.
#
# At this point three expenses involve the Alex/Sam pair:
#   EXPENSE1        - direct, Alex paid, split Alex+Sam
#   EXPENSE_SAM_PAID - direct, Sam paid,  split Alex+Sam
#   EXPENSE2        - GROUP (Trip), Alex paid, split Alex+Sam+Priya
# All three contribute to get_friend_balance(Alex, Sam), so all three must
# show in Alex's history for Sam. The group one (EXPENSE2) is the
# regression: the original group_id-is-null filter dropped it, producing a
# non-zero balance with a missing line item.
shared_json=$(supabase db query --linked --output-format json "
  set local role authenticated;
  set local request.jwt.claim.sub = '$ALEX';
  select
    (select count(*)::int from get_shared_expenses('$SAM')) as total,
    (select count(*)::int from get_shared_expenses('$SAM') where id = '$EXPENSE2') as has_group;
" 2>/dev/null)
shared_total=$(echo "$shared_json" | jq -r '.rows[0].total // "null"')
shared_has_group=$(echo "$shared_json" | jq -r '.rows[0].has_group // "null"')
if [[ "$shared_total" == "3" && "$shared_has_group" == "1" ]]; then
  echo "ok - get_shared_expenses returns all three shared expenses incl. the group one"
  pass_count=$((pass_count + 1))
else
  echo "not ok - get_shared_expenses missing shared expenses (total: $shared_total, has_group: $shared_has_group)"
  fail_count=$((fail_count + 1))
fi

# get_friend_activity must decompose get_friend_balance into displayable
# rows. Reads auth.uid(), so run under the authenticated role like the
# other RLS-sensitive checks. Using the existing Alex/Sam/Priya fixtures:
#   EXPENSE1        - direct, Alex paid 1000, split 500/500  -> Sam owes Alex 500
#   EXPENSE_SAM_PAID - direct, Sam paid 300, split 150/150   -> Alex owes Sam 150
#   EXPENSE2        - GROUP (Trip), Alex paid 300, 100 each  -> Sam owes Alex 100 pairwise
#   settlements: Sam->Alex 500 (direct), Alex->Sam 200 (direct),
#                Sam->Alex 100 (group Trip)
activity_json=$(supabase db query --linked --output-format json "
  set local role authenticated;
  set local request.jwt.claim.sub = '$ALEX';
  select
    (select count(*)::int from get_friend_activity('$SAM') where kind = 'expense')    as expenses,
    (select count(*)::int from get_friend_activity('$SAM') where kind = 'group')      as groups,
    (select count(*)::int from get_friend_activity('$SAM') where kind = 'settlement') as settlements,
    (select net from get_friend_activity('$SAM') where kind = 'group' and ref_id = '$TRIP_GROUP') as trip_net,
    (select round(sum(net), 2) from get_friend_activity('$SAM')) as total,
    get_friend_balance('$ALEX', '$SAM') as balance;
" 2>/dev/null || true)
a_exp=$(echo "$activity_json" | jq -r '.rows[0].expenses // "null"')
a_grp=$(echo "$activity_json" | jq -r '.rows[0].groups // "null"')
a_set=$(echo "$activity_json" | jq -r '.rows[0].settlements // "null"')
a_trip=$(echo "$activity_json" | jq -r '.rows[0].trip_net // "null"')
a_total=$(echo "$activity_json" | jq -r '.rows[0].total // "null"')
a_balance=$(echo "$activity_json" | jq -r '.rows[0].balance // "null"')

if [[ "$a_exp" == "2" && "$a_grp" == "1" && "$a_set" == "2" ]]; then
  echo "ok - get_friend_activity returns 2 direct expenses, 1 group row, 2 direct settlements"
  pass_count=$((pass_count + 1))
else
  echo "not ok - get_friend_activity row kinds (expenses: $a_exp, groups: $a_grp, settlements: $a_set)"
  fail_count=$((fail_count + 1))
fi

# Trip group row must reflect the pairwise Alex<->Sam net inside the group
# (Alex paid 300 split 100 each => Sam owes Alex 100; group settlement
# Sam->Alex 100 clears it), NOT the simplified group debt.
if [[ "$a_trip" == "0.00" || "$a_trip" == "0" ]]; then
  echo "ok - get_friend_activity Trip group row nets the in-group pairwise balance to 0"
  pass_count=$((pass_count + 1))
else
  echo "not ok - get_friend_activity Trip group net (actual: $a_trip, expected 0)"
  fail_count=$((fail_count + 1))
fi

# Reconciliation: the rows must sum to the header balance exactly.
if [[ "$a_total" != "null" && "$a_total" == "$a_balance" ]]; then
  echo "ok - get_friend_activity rows sum to get_friend_balance ($a_total)"
  pass_count=$((pass_count + 1))
else
  echo "not ok - get_friend_activity reconciliation (sum: $a_total, balance: $a_balance)"
  fail_count=$((fail_count + 1))
fi

echo "$pass_count passed, $fail_count failed"
[[ "$fail_count" -eq 0 ]]
