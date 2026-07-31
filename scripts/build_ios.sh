#!/usr/bin/env bash
# Builds the iOS app against the linked cloud Supabase project, wiring up
# SUPABASE_URL/SUPABASE_ANON_KEY as dart-defines (see lib/main.dart) — same
# approach as scripts/run_dev.sh, but producing a build artifact instead of
# running on an attached device.
#
# Unlike Android, this rarely hands you a drag-and-drop-installable file:
# a real-device build still needs a Development Team selected in Xcode
# (open ios/Runner.xcworkspace) to sign and install, since Apple requires
# that regardless of how the underlying build was produced. For testing on
# your own cabled device without dealing with that, `scripts/run_dev.sh
# <device-id>` is the easier path. This script is mainly useful for a
# --simulator build (no signing needed) or to produce
# build/ios/iphoneos/Runner.app for Xcode to pick up and sign/install from.
#
# The anon key is fetched fresh from the Supabase API each run via the
# CLI, rather than stored in the repo or a local .env file.
#
# Usage:
#   scripts/build_ios.sh [debug|profile|release] [-- <extra flutter build args>]
#
# Examples:
#   scripts/build_ios.sh                      # release build (default)
#   scripts/build_ios.sh debug --simulator    # no code signing required
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

exec flutter build ios "--$MODE" \
  --dart-define="SUPABASE_URL=${SUPABASE_URL}" \
  --dart-define="SUPABASE_ANON_KEY=${ANON_KEY}" \
  --dart-define="FEED_TESTING_UNLIMITED=true" \
  "$@"
