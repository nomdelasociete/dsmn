#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/DerivedData/Build/Products/Debug/dsmn.app}"
HELPER_PATH="$APP_PATH/Contents/Library/LaunchDaemons/dsmnd"
CTL_PATH="$APP_PATH/Contents/Library/Helpers/dsmnctl"
PLIST_PATH="$APP_PATH/Contents/Library/LaunchDaemons/com.nomdelasociete.dsmn.helper.plist"
INFO_PLIST="$APP_PATH/Contents/Info.plist"

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

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "Info.plist missing: $INFO_PLIST" >&2
  exit 2
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign --verify --strict --verbose=2 "$HELPER_PATH"
codesign --verify --strict --verbose=2 "$CTL_PATH"

VERIFY_STATE_DIR="$(mktemp -d)"
trap 'rm -rf "$VERIFY_STATE_DIR"' EXIT
DSMN_STATE_DIR="$VERIFY_STATE_DIR" "$CTL_PATH" status --json >/dev/null
DSMN_STATE_DIR="$VERIFY_STATE_DIR" DSMN_APPLY_PMSET=0 "$HELPER_PATH" daemon-once >/dev/null

plutil -lint "$PLIST_PATH"
plutil -p "$PLIST_PATH"

if [[ "${DSMN_REQUIRE_SPARKLE:-0}" == "1" ]]; then
  feed_url="$(plutil -extract SUFeedURL raw -o - "$INFO_PLIST" 2>/dev/null || true)"
  public_key="$(plutil -extract SUPublicEDKey raw -o - "$INFO_PLIST" 2>/dev/null || true)"

  if [[ -z "$feed_url" || "$feed_url" == *'$('* ]]; then
    echo "release bundle missing resolved SUFeedURL in $INFO_PLIST" >&2
    exit 2
  fi

  if [[ -z "$public_key" || "$public_key" == *'$('* ]]; then
    echo "release bundle missing resolved SUPublicEDKey in $INFO_PLIST" >&2
    exit 2
  fi
fi
