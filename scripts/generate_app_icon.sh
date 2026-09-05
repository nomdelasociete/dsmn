#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_PATH="${1:-$ROOT_DIR/Sources/dsmnapp/Resources/dsmn.icns}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
iconset="$tmp_dir/dsmn.iconset"
mkdir -p "$iconset" "$(dirname "$OUT_PATH")"

xcrun swiftc "$ROOT_DIR/Sources/dsmnapp/Views/DSMNIdentity.swift" \
  "$ROOT_DIR/scripts/render_app_icon.swift" -o "$tmp_dir/render-icon"
"$tmp_dir/render-icon" "$iconset"
iconutil -c icns "$iconset" -o "$OUT_PATH"
echo "Generated $OUT_PATH from the website heartbeat identity"
