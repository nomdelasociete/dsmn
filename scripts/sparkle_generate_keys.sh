#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENERATE_KEYS="${SPARKLE_GENERATE_KEYS:-}"
SPARKLE_KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-nomdelasociete-dsmn}"

find_tool() {
  if [[ -n "$GENERATE_KEYS" && -x "$GENERATE_KEYS" ]]; then
    printf '%s\n' "$GENERATE_KEYS"
    return 0
  fi

  for root in \
    "$ROOT_DIR/.build" \
    "$ROOT_DIR/DerivedData" \
    "$HOME/Library/Developer/Xcode/DerivedData"; do
    [[ -d "$root" ]] || continue
    local match
    match="$(find "$root" -type f -name generate_keys -perm -111 2>/dev/null | head -n 1 || true)"
    if [[ -n "$match" ]]; then
      printf '%s\n' "$match"
      return 0
    fi
  done

  return 1
}

TOOL="$(find_tool || true)"
if [[ -z "$TOOL" ]]; then
  echo "Sparkle generate_keys tool not found." >&2
  echo "Run xcodebuild once, or set SPARKLE_GENERATE_KEYS=/path/to/generate_keys." >&2
  exit 2
fi

"$TOOL" --account "$SPARKLE_KEY_ACCOUNT" "$@"
