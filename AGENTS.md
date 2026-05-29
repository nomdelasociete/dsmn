# dsmn Agent Notes

## Operating Rules

- Always run `git fetch --all --prune` and check `git status --short --branch`
  before changing code.
- Keep changes scoped and commit/push each completed step.
- Do not revert unrelated user changes.
- Use `apply_patch` for manual file edits.
- Prefer `rg` and `rg --files` for repository search.

## Product Context

`dsmn` is a macOS menu bar app that intentionally keeps the Mac awake during
local AI coding sessions, including closed-lid cases where plain `caffeinate`
is insufficient.

The helper daemon is the only component allowed to change:

```sh
pmset -a disablesleep 1
```

The app, Raycast extension, hooks, and `dsmnctl` express intent; the privileged
helper owns the actual power-management operation.

## Main Components

- `Sources/DSMNCore`: state, process detection, snapshots, decision engine,
  hook installation, XPC client, and CLI-facing models.
- `Sources/dsmnapp`: SwiftUI menu bar app and helper registration UI.
- `Sources/dsmnd`: privileged helper daemon and XPC service.
- `Sources/dsmnctl`: CLI used by the app, hooks, Raycast, and debugging.
- `raycast`: Raycast remote-control extension.
- `docs`: architecture, safety, hooks, Raycast, macOS app, and packaging notes.

## Supported Agents

`dsmnctl install-hooks` supports:

- Claude Code
- Codex
- Grok Build
- Pi

All installed hooks call the shared script:

```sh
~/.dsmn/dsmn-agent-hook.sh
```

The script calls `dsmnctl manual --minutes 20 --extend-only --requester <agent>`
by default, records the last requester when possible, and falls back to
`caffeinate -is -t 600` only if `dsmnctl` or the helper is unavailable.

## Build And Test

Use these checks for normal changes:

```sh
swift test
xcodegen generate
xcodebuild -project dsmn.xcodeproj -scheme dsmn -configuration Debug -destination 'platform=macOS' -derivedDataPath DerivedData build
./scripts/verify_bundle.sh DerivedData/Build/Products/Debug/dsmn.app
```

For distribution-affecting changes:

```sh
./scripts/archive.sh
./scripts/verify_bundle.sh dist/export/dsmn.app
AC_NOTARY_PROFILE=dsmn-notary ./scripts/notarize.sh dist/export/dsmn.app
ditto -c -k --keepParent dist/export/dsmn.app dist/dsmn-notarized.zip
```

For Raycast changes:

```sh
npm run build --prefix raycast
```

## Runtime Verification

Useful commands:

```sh
dist/export/dsmn.app/Contents/Library/Helpers/dsmnctl doctor
pmset -g live | rg 'SleepDisabled|sleep'
tail -n 20 /tmp/dsmn-agent-hook.log
```

Expected protected state:

```text
Status source: helper
Power lock: on
macOS SleepDisabled: on
SleepDisabled 1
```

## Safety Notes

- Auto mode prevents sleep only while a supported agent process is detected and
  recent hook or auto-enable activity is still fresh.
- Auto mode releases the lock when activity is stale, when no agent is detected,
  when the network route is unavailable, or when battery is at or below the
  configured threshold.
- Hooks create bounded manual leases; repeated tool calls renew the lease
  without adding time or shortening a longer manual timer.
- Hooks record the last requester, for example `Codex - dsmn - session abc12345`
  when the hook payload exposes session context.
- dsmn does not intentionally keep the display awake.
