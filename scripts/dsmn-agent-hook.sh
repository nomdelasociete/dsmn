#!/usr/bin/env bash
set -u

MINUTES="${DSMN_HOOK_MINUTES:-20}"
FALLBACK_SECONDS="${DSMN_HOOK_FALLBACK_SECONDS:-600}"
LOG_PATH="${DSMN_HOOK_LOG:-/tmp/dsmn-agent-hook.log}"
HOOK_AGENT="${DSMN_HOOK_AGENT:-agent}"
HOOK_EVENT="${DSMN_HOOK_EVENT:-}"
HOOK_PAYLOAD=""
if [[ ! -t 0 ]]; then
  HOOK_PAYLOAD="$(head -c 65536 2>/dev/null || true)"
fi

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

requester_name() {
  case "$HOOK_AGENT" in
  claude)
    printf '%s\n' "Claude Code"
    ;;
  codex)
    printf '%s\n' "Codex"
    ;;
  grok)
    printf '%s\n' "Grok Build"
    ;;
  pi)
    printf '%s\n' "Pi"
    ;;
  *)
    printf '%s\n' "Agent"
    ;;
  esac
}

json_value() {
  local key="$1"
  command -v python3 >/dev/null 2>&1 || return 0

  JSON_KEY="$key" python3 -c '
import json
import os
import sys

key = os.environ.get("JSON_KEY")

try:
    root = json.load(sys.stdin)
except Exception:
    sys.exit(0)

def find(value):
    if isinstance(value, dict):
        if key in value and value[key] not in (None, ""):
            return value[key]
        for child in value.values():
            found = find(child)
            if found not in (None, ""):
                return found
    elif isinstance(value, list):
        for child in value:
            found = find(child)
            if found not in (None, ""):
                return found
    return None

found = find(root)
if found not in (None, ""):
    text = str(found).replace("\n", " ").replace("\r", " ").strip()
    print(text[:200])
' <<<"$HOOK_PAYLOAD" 2>/dev/null || true
}

short_session() {
  local value="$1"
  value="${value##*/}"
  value="${value%.jsonl}"
  value="${value%.json}"
  printf '%.8s\n' "$value"
}

hook_context() {
  local session_id cwd project session_short
  session_id="$(json_value "session_id")"
  [[ -z "$session_id" ]] && session_id="$(json_value "sessionId")"
  [[ -z "$session_id" ]] && session_id="$(json_value "conversation_id")"
  [[ -z "$session_id" ]] && session_id="$(json_value "conversationId")"
  [[ -z "$session_id" ]] && session_id="$(json_value "transcript_path")"

  cwd="$(json_value "cwd")"
  [[ -z "$cwd" ]] && cwd="$(json_value "project_dir")"
  [[ -z "$cwd" ]] && cwd="$(json_value "project")"
  [[ -z "$cwd" && -n "${PWD:-}" ]] && cwd="$PWD"

  project="${cwd##*/}"
  session_short=""
  if [[ -n "$session_id" ]]; then
    session_short="$(short_session "$session_id")"
  fi

  if [[ -n "$project" && -n "$session_short" ]]; then
    printf '%s\n' "$project - session $session_short"
  elif [[ -n "$session_short" ]]; then
    printf '%s\n' "session $session_short"
  elif [[ -n "$project" && "$project" != "." ]]; then
    printf '%s\n' "$project"
  fi
}

hook_event() {
  if [[ -n "$HOOK_EVENT" ]]; then
    printf '%s\n' "$HOOK_EVENT"
    return 0
  fi

  local event
  event="$(json_value "hook_event_name")"
  [[ -z "$event" ]] && event="$(json_value "hookEventName")"
  [[ -z "$event" ]] && event="$(json_value "eventName")"
  [[ -z "$event" ]] && event="$(json_value "event")"
  printf '%s\n' "$event"
}

ctl="$(resolve_dsmnctl || true)"
if [[ -z "$ctl" ]]; then
  log_event "dsmnctl not found"
  fallback_caffeinate
  exit 0
fi

REQUESTER_NAME="$(requester_name)"
REQUESTER_CONTEXT="$(hook_context)"
REQUESTER_EVENT="$(hook_event)"

manual_args=(manual --minutes "$MINUTES" --extend-only --requester "$REQUESTER_NAME" --json)
[[ -n "$REQUESTER_CONTEXT" ]] && manual_args+=(--context "$REQUESTER_CONTEXT")
[[ -n "$REQUESTER_EVENT" ]] && manual_args+=(--event "$REQUESTER_EVENT")

if ! "$ctl" "${manual_args[@]}" >/dev/null 2>&1; then
  log_event "dsmn manual failed ctl=$ctl requester=$REQUESTER_NAME"
  fallback_caffeinate
  exit 0
fi

doctor="$("$ctl" doctor 2>&1 || true)"

if grep -q "Status source: local fallback" <<<"$doctor"; then
  log_event "helper unavailable; using fallback"
  fallback_caffeinate
  exit 0
fi

if grep -q "macOS SleepDisabled: on" <<<"$doctor"; then
  log_event "dsmn active minutes=$MINUTES requester=$REQUESTER_NAME context=$REQUESTER_CONTEXT event=$REQUESTER_EVENT"
else
  log_event "dsmn helper reachable but sleep lock is off"
fi

exit 0
