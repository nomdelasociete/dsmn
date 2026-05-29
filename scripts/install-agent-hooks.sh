#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_CTL="$ROOT/dist/export/dsmn.app/Contents/Library/Helpers/dsmnctl"
DEBUG_CTL="$ROOT/.build/debug/dsmnctl"

supports_install_hooks() {
  "$1" help 2>/dev/null | grep -q 'install-hooks'
}

if [[ -x "$DIST_CTL" ]] && supports_install_hooks "$DIST_CTL"; then
  exec "$DIST_CTL" install-hooks "$@"
fi

if [[ -x "$DEBUG_CTL" ]] && supports_install_hooks "$DEBUG_CTL"; then
  exec "$DEBUG_CTL" install-hooks "$@"
fi

exec swift run --package-path "$ROOT" dsmnctl install-hooks "$@"
