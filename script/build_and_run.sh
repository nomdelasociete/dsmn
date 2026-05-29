#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
SCHEME="dsmn"
APP_NAME="dsmn"
PROCESS_NAME="dsmn"
BUNDLE_ID="com.nomdelasociete.dsmn"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/DerivedData"
PROJECT="$ROOT_DIR/dsmn.xcodeproj"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"

cd "$ROOT_DIR"

xcodegen generate --use-cache

pkill -x "$PROCESS_NAME" >/dev/null 2>&1 || true

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  build

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BUNDLE/Contents/MacOS/$PROCESS_NAME"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$PROCESS_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$PROCESS_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
