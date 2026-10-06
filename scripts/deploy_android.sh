#!/usr/bin/env bash
# Builds the release Android APK and uploads it to Google Drive
# (gdrive:apps/meowes) for sideload testing.
#
# Always builds with --split-per-abi and uploads the arm64 split. Split APKs
# carry versionCode = build-number + 1000*abi-offset (arm64 -> 2001 for
# 1.0.0+1); the app installed on the test phone is the arm64 split, so
# uploading the universal APK (versionCode 1) would be rejected by Android
# as a downgrade ("package appears to be invalid").
#
# Builds go through scripts/build_android.sh so the Supabase dart-defines are
# injected (a bare `flutter build` produces an APK that can't reach the
# backend).
#
# Usage:
#   scripts/deploy_android.sh              # build + upload arm64 split
#   scripts/deploy_android.sh --migrate    # also `supabase db push` first
#   scripts/deploy_android.sh --all        # upload every ABI split
#   scripts/deploy_android.sh --no-build   # upload the existing build output
#
# Requires: rclone with a "gdrive:" remote, plus everything build_android.sh
# needs (supabase CLI logged in + linked, jq). aapt (Android SDK build-tools)
# is optional; when found it is used to check the versionCode.

set -euo pipefail
cd "$(dirname "$0")/.."

REMOTE_DIR="${DEPLOY_REMOTE_DIR:-gdrive:apps/meowes}"
OUT_DIR="build/app/outputs/flutter-apk"

MIGRATE=0
ALL=0
BUILD=1
for arg in "$@"; do
  case "$arg" in
    --migrate)  MIGRATE=1 ;;
    --all)      ALL=1 ;;
    --no-build) BUILD=0 ;;
    *) echo "error: unknown option $arg" >&2; exit 1 ;;
  esac
done

if ! command -v rclone >/dev/null 2>&1; then
  echo "error: rclone is required (brew install rclone) with a 'gdrive:' remote." >&2
  exit 1
fi
if ! rclone listremotes 2>/dev/null | grep -qx "${REMOTE_DIR%%:*}:"; then
  echo "error: rclone remote '${REMOTE_DIR%%:*}:' not configured (rclone config)." >&2
  exit 1
fi

if [[ "$MIGRATE" == 1 ]]; then
  echo "==> Pushing Supabase migrations"
  supabase db push --yes
fi

if [[ "$BUILD" == 1 ]]; then
  echo "==> Building release APKs (split per ABI)"
  scripts/build_android.sh release --split-per-abi
fi

if [[ "$ALL" == 1 ]]; then
  FILES=("$OUT_DIR"/app-*-release.apk)
else
  FILES=("$OUT_DIR/app-arm64-v8a-release.apk")
fi

AAPT="$(ls "${ANDROID_HOME:-$HOME/Library/Android/sdk}"/build-tools/*/aapt 2>/dev/null | tail -n1 || true)"

for f in "${FILES[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "error: $f not found." >&2
    exit 1
  fi
  name="$(basename "$f")"

  if [[ -n "$AAPT" ]]; then
    code="$("$AAPT" dump badging "$f" | sed -n "s/.*versionCode='\([0-9]*\)'.*/\1/p" | head -n1)"
    if [[ "${code:-0}" -lt 1000 ]]; then
      echo "error: $name has versionCode $code — looks like a universal APK, not a split." >&2
      echo "Installing it over a split build would be rejected as a downgrade." >&2
      exit 1
    fi
    echo "==> $name versionCode=$code"
  fi

  echo "==> Uploading $name to $REMOTE_DIR"
  rclone copy "$f" "$REMOTE_DIR/"

  local_md5="$(md5 -q "$f" 2>/dev/null || md5sum "$f" | cut -d' ' -f1)"
  remote_md5="$(rclone md5sum "$REMOTE_DIR/$name" | awk '{print $1}')"
  if [[ "$local_md5" != "$remote_md5" ]]; then
    echo "error: checksum mismatch for $name (local $local_md5, remote $remote_md5)." >&2
    exit 1
  fi
  echo "    checksum OK ($local_md5)"
done

echo "Done. Download from Drive: apps/meowes/"
