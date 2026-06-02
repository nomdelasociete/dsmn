#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/dist/export/dsmn.app}"
ZIP_PATH="${ZIP_PATH:-$ROOT_DIR/dist/dsmn-notary.zip}"
NOTARY_PROFILE="${AC_NOTARY_PROFILE:-}"

if [[ -z "$NOTARY_PROFILE" ]]; then
  echo "AC_NOTARY_PROFILE is required. Create one with: xcrun notarytool store-credentials <profile-name>" >&2
  exit 2
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "app bundle not found: $APP_PATH" >&2
  exit 2
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign --verify --strict --verbose=2 "$APP_PATH/Contents/Library/LaunchDaemons/dsmnd"

rm -f "$ZIP_PATH"
/usr/bin/ditto -c -k --keepParent --sequesterRsrc --rsrc "$APP_PATH" "$ZIP_PATH"

xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl -a -vv --type execute "$APP_PATH"
