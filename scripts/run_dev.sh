#!/usr/bin/env bash
# Launches the app against the linked cloud Supabase project, wiring up
# SUPABASE_URL/SUPABASE_ANON_KEY as dart-defines (see lib/main.dart).
#
# The anon key is fetched fresh from the Supabase API each run via the
# CLI, rather than stored in the repo or a local .env file.
#
# FEED_TESTING_UNLIMITED is set to false, so the feed screen's real
# client-side cooldown gate (lib/features/pet/feed_flow_screen.dart)
# applies here same as release builds. Flip to true locally for repeat
# feed testing — it doesn't bypass the server-side cooldown in the
# feed_pet() RPC either way, see that file's comment for details.
#
# Usage:
#   scripts/run_dev.sh [device-id] [-- <extra flutter run args>]
#
# Requires: `supabase` CLI logged in (`supabase login`) with this project
# linked (`supabase link`), and `jq`.

set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT_REF_FILE="supabase/.temp/project-ref"
if [[ ! -f "$PROJECT_REF_FILE" ]]; then
  echo "error: no linked Supabase project found (missing $PROJECT_REF_FILE)." >&2
  echo "Run 'supabase link --project-ref <ref>' first." >&2
  exit 1
fi
PROJECT_REF="$(cat "$PROJECT_REF_FILE")"

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required (brew install jq)." >&2
  exit 1
fi

ANON_KEY="$(supabase projects api-keys --project-ref "$PROJECT_REF" --output-format json \
  | jq -r '.keys[] | select(.type == "publishable" or .id == "anon") | .api_key' \
  | head -n1)"

if [[ -z "$ANON_KEY" || "$ANON_KEY" == "null" ]]; then
  echo "error: could not fetch an anon/publishable API key for project $PROJECT_REF." >&2
  exit 1
fi

SUPABASE_URL="https://${PROJECT_REF}.supabase.co"

DEVICE="${1:-}"
if [[ -n "$DEVICE" ]]; then
  shift
fi

DEVICE_ARGS=()
if [[ -n "$DEVICE" ]]; then
  DEVICE_ARGS=(-d "$DEVICE")
fi

exec flutter run "${DEVICE_ARGS[@]}" \
  --dart-define="SUPABASE_URL=${SUPABASE_URL}" \
  --dart-define="SUPABASE_ANON_KEY=${ANON_KEY}" \
  --dart-define="FEED_TESTING_UNLIMITED=false" \
  "$@"
