#!/usr/bin/env bash
# Builds an installable Android APK against the linked cloud Supabase
# project, wiring up SUPABASE_URL/SUPABASE_ANON_KEY as dart-defines (see
# lib/main.dart) — same approach as scripts/run_dev.sh, but producing a
# standalone .apk instead of running on an attached device.
#
# The release build type is currently signed with the debug key (see the
# TODO in android/app/build.gradle), so either mode works for local/friend
# testing without a real release keystore, and both carry the debug SHA-1
# already registered for Google sign-in.
#
# The anon key is fetched fresh from the Supabase API each run via the
# CLI, rather than stored in the repo or a local .env file.
#
# Usage:
#   scripts/build_android.sh [debug|profile|release] [-- <extra flutter build args>]
#
# Examples:
#   scripts/build_android.sh                      # release APK (default)
#   scripts/build_android.sh debug
#   scripts/build_android.sh release --split-per-abi
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

MODE="release"
case "${1:-}" in
  debug|profile|release)
    MODE="$1"
    shift
    ;;
esac

# Only debug builds skip the feed cooldown gate (see the flag's doc comment
# in lib/features/pet/feed_flow_screen.dart) — release/profile builds
# should behave like the real app, cooldown included. Branched into two
# exec calls rather than building an optional array: macOS ships bash 3.2,
# where "${arr[@]}" on an empty array errors out under `set -u`.
if [[ "$MODE" == "debug" ]]; then
  exec flutter build apk "--$MODE" \
    --dart-define="SUPABASE_URL=${SUPABASE_URL}" \
    --dart-define="SUPABASE_ANON_KEY=${ANON_KEY}" \
    --dart-define="FEED_TESTING_UNLIMITED=true" \
    "$@"
else
  exec flutter build apk "--$MODE" \
    --dart-define="SUPABASE_URL=${SUPABASE_URL}" \
    --dart-define="SUPABASE_ANON_KEY=${ANON_KEY}" \
    "$@"
fi
