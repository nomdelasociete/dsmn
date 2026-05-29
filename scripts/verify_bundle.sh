#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/DerivedData/Build/Products/Debug/dsmn.app}"
HELPER_PATH="$APP_PATH/Contents/Library/LaunchDaemons/dsmnd"
CTL_PATH="$APP_PATH/Contents/Library/Helpers/dsmnctl"
PLIST_PATH="$APP_PATH/Contents/Library/LaunchDaemons/com.nomdelasociete.dsmn.helper.plist"

if [[ ! -d "$APP_PATH" ]]; then
  echo "app bundle not found: $APP_PATH" >&2
  exit 2
fi

if [[ ! -x "$HELPER_PATH" ]]; then
  echo "helper missing or not executable: $HELPER_PATH" >&2
  exit 2
fi

if [[ ! -x "$CTL_PATH" ]]; then
  echo "dsmnctl missing or not executable: $CTL_PATH" >&2
  exit 2
fi

if [[ ! -f "$PLIST_PATH" ]]; then
  echo "LaunchDaemon plist missing: $PLIST_PATH" >&2
  exit 2
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign --verify --strict --verbose=2 "$HELPER_PATH"
codesign --verify --strict --verbose=2 "$CTL_PATH"
plutil -lint "$PLIST_PATH"
plutil -p "$PLIST_PATH"
