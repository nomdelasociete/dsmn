#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON_DOC="${1:-$ROOT_DIR/docs/dsmn logo.icon}"
OUT_PATH="${2:-$ROOT_DIR/Sources/dsmnapp/Resources/dsmn.icns}"
ICTOOL="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"

if [[ ! -x "$ICTOOL" ]]; then
  echo "Icon Composer ictool not found: $ICTOOL" >&2
  exit 2
fi

if [[ ! -d "$ICON_DOC" ]]; then
  echo "Icon Composer document not found: $ICON_DOC" >&2
  exit 2
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

iconset="$tmp_dir/dsmn.iconset"
mkdir -p "$iconset" "$(dirname "$OUT_PATH")"

export_icon() {
  local name="$1"
  local pixels="$2"
  "$ICTOOL" "$ICON_DOC" \
    --export-image \
    --output-file "$iconset/$name" \
    --platform macOS \
    --rendition Default \
    --width "$pixels" \
    --height "$pixels" \
    --scale 1 >/dev/null
}

export_icon icon_16x16.png 16
export_icon icon_16x16@2x.png 32
export_icon icon_32x32.png 32
export_icon icon_32x32@2x.png 64
export_icon icon_128x128.png 128
export_icon icon_128x128@2x.png 256
export_icon icon_256x256.png 256
export_icon icon_256x256@2x.png 512
export_icon icon_512x512.png 512
export_icon icon_512x512@2x.png 1024

iconutil -c icns "$iconset" -o "$OUT_PATH"
echo "Generated $OUT_PATH from $ICON_DOC"
