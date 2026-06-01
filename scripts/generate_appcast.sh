#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATE_ARCHIVE="${1:-$ROOT_DIR/dist/dsmn-notarized.zip}"
UPDATES_DIR="${UPDATES_DIR:-$ROOT_DIR/dist/updates}"
RELEASE_NOTES="${RELEASE_NOTES:-}"
GENERATE_APPCAST="${SPARKLE_GENERATE_APPCAST:-}"
SPARKLE_KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-nomdelasociete-dsmn}"
DSMN_UPDATE_FEED_URL="${DSMN_UPDATE_FEED_URL:-https://nomdelasociete.github.io/dsmn/appcast.xml}"
DSMN_UPDATE_BASE_URL="${DSMN_UPDATE_BASE_URL:-${DSMN_UPDATE_FEED_URL%/*}}"

if [[ "$DSMN_UPDATE_BASE_URL" != */ ]]; then
  DSMN_UPDATE_BASE_URL="$DSMN_UPDATE_BASE_URL/"
fi

find_tool() {
  if [[ -n "$GENERATE_APPCAST" && -x "$GENERATE_APPCAST" ]]; then
    printf '%s\n' "$GENERATE_APPCAST"
    return 0
  fi

  for root in \
    "$ROOT_DIR/.build" \
    "$ROOT_DIR/DerivedData" \
    "$HOME/Library/Developer/Xcode/DerivedData"; do
    [[ -d "$root" ]] || continue
    local match
    match="$(find "$root" -type f -name generate_appcast -perm -111 2>/dev/null | head -n 1 || true)"
    if [[ -n "$match" ]]; then
      printf '%s\n' "$match"
      return 0
    fi
  done

  return 1
}

if [[ ! -f "$UPDATE_ARCHIVE" ]]; then
  echo "update archive not found: $UPDATE_ARCHIVE" >&2
  exit 2
fi

TOOL="$(find_tool || true)"
if [[ -z "$TOOL" ]]; then
  echo "Sparkle generate_appcast tool not found." >&2
  echo "Run xcodebuild once, or set SPARKLE_GENERATE_APPCAST=/path/to/generate_appcast." >&2
  exit 2
fi

mkdir -p "$UPDATES_DIR"
cp "$UPDATE_ARCHIVE" "$UPDATES_DIR/"

if [[ -n "$RELEASE_NOTES" ]]; then
  if [[ ! -f "$RELEASE_NOTES" ]]; then
    echo "release notes file not found: $RELEASE_NOTES" >&2
    exit 2
  fi

  archive_name="$(basename "$UPDATE_ARCHIVE")"
  notes_ext="${RELEASE_NOTES##*.}"
  cp "$RELEASE_NOTES" "$UPDATES_DIR/${archive_name%.*}.$notes_ext"
fi

"$TOOL" \
  --account "$SPARKLE_KEY_ACCOUNT" \
  --download-url-prefix "$DSMN_UPDATE_BASE_URL" \
  --release-notes-url-prefix "$DSMN_UPDATE_BASE_URL" \
  "$UPDATES_DIR"
