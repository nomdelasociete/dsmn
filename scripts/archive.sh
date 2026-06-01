#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/dsmn.xcodeproj"
SCHEME="dsmn"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT_DIR/dist/dsmn.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$ROOT_DIR/dist/export}"
EXPORT_OPTIONS="${EXPORT_OPTIONS:-$ROOT_DIR/macos/ExportOptions.plist}"
EXPORT="${EXPORT:-1}"
DSMN_UPDATE_FEED_URL="${DSMN_UPDATE_FEED_URL:-https://dsmn.app/appcast.xml}"
DSMN_SPARKLE_PUBLIC_ED_KEY="${DSMN_SPARKLE_PUBLIC_ED_KEY:-}"

if [[ -z "$DSMN_SPARKLE_PUBLIC_ED_KEY" ]]; then
  echo "DSMN_SPARKLE_PUBLIC_ED_KEY is required for Release archives." >&2
  echo "Generate it once with: ./scripts/sparkle_generate_keys.sh" >&2
  exit 2
fi

cd "$ROOT_DIR"

xcodegen generate --use-cache
mkdir -p "$ROOT_DIR/dist"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=JSFMAD28GS \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DSMN_UPDATE_FEED_URL="$DSMN_UPDATE_FEED_URL" \
  DSMN_SPARKLE_PUBLIC_ED_KEY="$DSMN_SPARKLE_PUBLIC_ED_KEY" \
  clean archive

if [[ "$EXPORT" == "1" ]]; then
  rm -rf "$EXPORT_PATH"
  xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS"
fi
