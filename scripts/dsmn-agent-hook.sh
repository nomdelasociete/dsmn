#!/usr/bin/env bash
set -u

MODE="${DSMN_HOOK_MODE:-manual}"
MINUTES="${DSMN_HOOK_MINUTES:-20}"
FALLBACK_SECONDS="${DSMN_HOOK_FALLBACK_SECONDS:-600}"
LOG_PATH="${DSMN_HOOK_LOG:-/tmp/dsmn-agent-hook.log}"

log_event() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG_PATH" 2>/dev/null || true
}

repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

resolve_dsmnctl() {
  if [[ -n "${DSMNCTL_PATH:-}" && -x "$DSMNCTL_PATH" ]]; then
    printf '%s\n' "$DSMNCTL_PATH"
    return 0
  fi

  local root
  root="$(repo_root)"

  local candidates=(
    "/Applications/dsmn.app/Contents/Library/Helpers/dsmnctl"
    "$HOME/Applications/dsmn.app/Contents/Library/Helpers/dsmnctl"
    "$root/dist/export/dsmn.app/Contents/Library/Helpers/dsmnctl"
    "$root/.build/debug/dsmnctl"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

fallback_caffeinate() {
  if ! command -v caffeinate >/dev/null 2>&1; then
    log_event "fallback unavailable: caffeinate not found"
    return 0
  fi

  caffeinate -is -t "$FALLBACK_SECONDS" >/dev/null 2>&1 &
  disown "$!" 2>/dev/null || true
  log_event "fallback caffeinate started seconds=$FALLBACK_SECONDS"
}

ctl="$(resolve_dsmnctl || true)"
if [[ -z "$ctl" ]]; then
  log_event "dsmnctl not found"
  fallback_caffeinate
  exit 0
fi

case "$MODE" in
manual)
  if ! "$ctl" manual --minutes "$MINUTES" --json >/dev/null 2>&1; then
    log_event "dsmn manual failed ctl=$ctl"
    fallback_caffeinate
    exit 0
  fi
  ;;
auto)
  if ! "$ctl" auto on --json >/dev/null 2>&1; then
    log_event "dsmn auto failed ctl=$ctl"
    fallback_caffeinate
    exit 0
  fi
  ;;
*)
  log_event "invalid mode=$MODE"
  fallback_caffeinate
  exit 0
  ;;
esac

doctor="$("$ctl" doctor 2>&1 || true)"

if grep -q "Status source: local fallback" <<<"$doctor"; then
  log_event "helper unavailable; using fallback"
  fallback_caffeinate
  exit 0
fi

if grep -q "macOS SleepDisabled: on" <<<"$doctor"; then
  log_event "dsmn active mode=$MODE minutes=$MINUTES"
else
  log_event "dsmn helper reachable but sleep lock is off"
fi

exit 0
