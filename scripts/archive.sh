#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/dsmn.xcodeproj"
SCHEME="dsmn"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT_DIR/dist/dsmn.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$ROOT_DIR/dist/export}"
EXPORT_OPTIONS="${EXPORT_OPTIONS:-$ROOT_DIR/macos/ExportOptions.plist}"
EXPORT="${EXPORT:-1}"

cd "$ROOT_DIR"

xcodegen generate --use-cache
mkdir -p "$ROOT_DIR/dist"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  clean archive

if [[ "$EXPORT" == "1" ]]; then
  rm -rf "$EXPORT_PATH"
  xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS"
fi
