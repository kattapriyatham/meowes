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

pass_count=0
fail_count=0

cleanup() {
  supabase db query --linked "
    delete from settlements where from_user in ('$ALEX','$SAM') or to_user in ('$ALEX','$SAM');
    delete from expense_splits where expense_id in ('$EXPENSE1', '$EXPENSE_SAM_PAID');
    delete from expenses where id in ('$EXPENSE1', '$EXPENSE_SAM_PAID');
    delete from users where id in ('$ALEX','$SAM');
    delete from auth.users where id in ('$ALEX','$SAM');
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

echo "$pass_count passed, $fail_count failed"
[[ "$fail_count" -eq 0 ]]
