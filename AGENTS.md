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
./scripts/generate_appcast.sh dist/dsmn-notarized.zip
```

## Release Guardrails

Do not treat a local archive as proof that a release is good. For any
release-bearing fix, publish the release and verify the public artifacts that a
real user or Sparkle will download.

After a merge or push to `main`, use the project slash command
`/release-dsmn [version] [build]` to run the full version bump, publish, and
public artifact verification flow. The command lives at
`.claude/commands/release-dsmn.md`.

Publishing a release does not automatically update the maintainer machine. If a
release changed hook installation or helper behavior, also check the local
`/Applications/dsmn.app`, helper `parent bundle version`, and installed
`~/.dsmn/dsmn-agent-hook.sh`. Reinstall hooks with
`/Applications/dsmn.app/Contents/Library/Helpers/dsmnctl install-hooks all`
after updating the local app.

After `./scripts/publish_release.sh`, verify:

```sh
curl -fsSL https://dsmn.app/appcast.xml -o /tmp/dsmn-appcast.xml
curl -fsSL https://dsmn.app/download/dsmn-latest.zip -o /tmp/dsmn-latest.zip
curl -fsSL https://dsmn.app/download/dsmn-latest.dmg -o /tmp/dsmn-latest.dmg
hdiutil verify /tmp/dsmn-latest.dmg
```

Extract the public ZIP and confirm the exact shipped app, not `dist/export`:

```sh
ditto -x -k /tmp/dsmn-latest.zip /tmp/dsmn-public
app=/tmp/dsmn-public/dsmn.app
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist"
codesign -v --deep --strict "$app"
spctl -a -vv --type execute "$app"
```

For XPC/client-auth changes, also verify nested code identifiers. Do not assume
`PRODUCT_BUNDLE_IDENTIFIER` controls the codesign identifier for command-line
targets.

Expected identifiers:

```text
dsmn.app: com.nomdelasociete.dsmn
dsmnctl: com.nomdelasociete.dsmn.dsmnctl
dsmnd: com.nomdelasociete.dsmn.helper
```

Use `codesign -dv` on nested binaries and fail the release if `dsmnctl` is
signed as plain `dsmnctl` or `dsmnd` is signed as plain `dsmnd`. If a bad
Sparkle release is already public, bump both marketing version and build number
before publishing the corrected build; Sparkle will not reliably replace a
same-build update.

For Raycast changes:

```sh
npm run build --prefix raycast
```

## Known Failure Modes

- A public release can be correct while the local `/Applications/dsmn.app` is
  stale. Always check the installed app version/build when investigating user
  reports:

  ```sh
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/dsmn.app/Contents/Info.plist
  /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' /Applications/dsmn.app/Contents/Info.plist
  ```

- Replacing or self-updating the app can leave `SMAppService` helper
  registration stale, unregistered, or attached to the previous parent bundle
  build. If hooks fire but closed-lid protection does not work, check both
  `dsmnctl doctor` and launchd:

  ```sh
  /Applications/dsmn.app/Contents/Library/Helpers/dsmnctl doctor
  launchctl print system/com.nomdelasociete.dsmn.helper
  ```

  Good state is `Status source: helper`, launchd `job state = running`, and
  `parent bundle version` matching the installed app build. If launchd says
  `spawn failed`, `EX_CONFIG`, `needs LWCR update`, or the helper is missing,
  use the app menu action `Update Helper`, `Repair Helper`, or `1. Install
  Helper`. Do not try to install the LaunchDaemon by copying files into
  `/Library/LaunchDaemons`; `SMAppService` must own registration.

- `Status: active` means a bounded dsmn timer is active. `Power lock: off` can
  still be expected while the lid is open after the grace window; the helper
  applies the macOS sleep lock only when the decision engine needs to prevent
  sleep. Do not diagnose this as a failed hook unless `doctor` reports
  `Status source: local fallback`, no active timer, or no recent requester.

- When diagnosing agent hooks, verify the shared hook and the last requester
  before changing detection logic:

  ```sh
  grep -n 'Status: active\|macOS SleepDisabled' ~/.dsmn/dsmn-agent-hook.sh
  tail -n 80 /tmp/dsmn-agent-hook.log
  /Applications/dsmn.app/Contents/Library/Helpers/dsmnctl status --json
  ```

  Grok Build should appear as `Grok Build` in `lastRequester` or
  `recentRequesters`. Reinstall hooks with `dsmnctl install-hooks all` after a
  release if the shared hook template changed.

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

- Hooks create bounded manual leases; repeated tool calls renew the lease
  without adding time or shortening a longer manual timer.
- Hooks record the last requester, for example `Codex - dsmn - session abc12345`
  when the hook payload exposes session context.
- Long-lived agent processes alone do not keep the Mac awake; dsmn only stays
  active while a manual timer is still valid.
- dsmn does not intentionally keep the display awake.
