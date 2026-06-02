#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${APP_PATH:-$ROOT_DIR/dist/export/dsmn.app}"
DMG_PATH="${DMG_PATH:-$ROOT_DIR/dist/dsmn.dmg}"
VOLUME_NAME="${VOLUME_NAME:-dsmn}"
SIGN_IDENTITY="${DSMN_DMG_CODE_SIGN_IDENTITY:-Developer ID Application: NOM DE LA SOCIETE (JSFMAD28GS)}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "app bundle not found: $APP_PATH" >&2
  exit 2
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

staging_dir="$(mktemp -d)"
trap 'rm -rf "$staging_dir"' EXIT

/usr/bin/ditto "$APP_PATH" "$staging_dir/dsmn.app"
ln -s /Applications "$staging_dir/Applications"

rm -f "$DMG_PATH"
mkdir -p "$(dirname "$DMG_PATH")"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$staging_dir" \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG_PATH"

if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" "$DMG_PATH"
fi

hdiutil verify "$DMG_PATH"

echo "Created $DMG_PATH"
