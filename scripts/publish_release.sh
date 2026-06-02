#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEBSITE_DIR="${DSMN_WEBSITE_DIR:-/Users/jb/Documents/Github/NomDeLaSociete/dsmn-website}"
NOTARY_PROFILE="${AC_NOTARY_PROFILE:-dsmn-notary}"
SPARKLE_KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-nomdelasociete-dsmn}"
PUBLIC_KEY="${DSMN_SPARKLE_PUBLIC_ED_KEY:-}"
APP_PATH="$ROOT_DIR/dist/export/dsmn.app"
UPDATES_DIR="$ROOT_DIR/dist/updates"

if [[ -z "$PUBLIC_KEY" ]]; then
  PUBLIC_KEY="$(SPARKLE_KEY_ACCOUNT="$SPARKLE_KEY_ACCOUNT" "$ROOT_DIR/scripts/sparkle_generate_keys.sh" -p 2>/dev/null || true)"
fi

if [[ -z "$PUBLIC_KEY" ]]; then
  echo "Sparkle public key not found." >&2
  echo "Run once: ./scripts/sparkle_generate_keys.sh" >&2
  exit 2
fi

if [[ ! -d "$WEBSITE_DIR" ]]; then
  echo "website repo not found: $WEBSITE_DIR" >&2
  exit 2
fi

export AC_NOTARY_PROFILE="$NOTARY_PROFILE"
export DSMN_SPARKLE_PUBLIC_ED_KEY="$PUBLIC_KEY"
export DSMN_UPDATE_FEED_URL="${DSMN_UPDATE_FEED_URL:-https://dsmn.app/appcast.xml}"
export DSMN_UPDATE_BASE_URL="${DSMN_UPDATE_BASE_URL:-https://dsmn.app/download/}"
export SPARKLE_KEY_ACCOUNT

cd "$ROOT_DIR"

"$ROOT_DIR/scripts/archive.sh"
DSMN_REQUIRE_SPARKLE=1 "$ROOT_DIR/scripts/verify_bundle.sh" "$APP_PATH"
"$ROOT_DIR/scripts/notarize.sh" "$APP_PATH"

version="$(plutil -extract CFBundleShortVersionString raw -o - "$APP_PATH/Contents/Info.plist")"
build="$(plutil -extract CFBundleVersion raw -o - "$APP_PATH/Contents/Info.plist")"
archive_path="$ROOT_DIR/dist/dsmn-${version}-${build}.zip"

rm -f "$archive_path"
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$archive_path"

rm -rf "$UPDATES_DIR"
UPDATES_DIR="$UPDATES_DIR" "$ROOT_DIR/scripts/generate_appcast.sh" "$archive_path"

if ! grep -q 'sparkle:edSignature' "$UPDATES_DIR/appcast.xml"; then
  echo "signed Sparkle appcast missing sparkle:edSignature" >&2
  exit 2
fi

(
  cd "$WEBSITE_DIR"
  railway run npm run upload:release -- --dir "$UPDATES_DIR"
)

curl -fsSI "$DSMN_UPDATE_FEED_URL" >/dev/null
curl -fsSI "${DSMN_UPDATE_BASE_URL%/}/dsmn-latest.zip" >/dev/null

echo "Published dsmn ${version} (${build})"
echo "Appcast: $DSMN_UPDATE_FEED_URL"
echo "Download: ${DSMN_UPDATE_BASE_URL%/}/dsmn-latest.zip"
