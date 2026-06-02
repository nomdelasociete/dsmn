# dsmn

`dsmn` means "don't stop me now".

It is a macOS utility for intentionally keeping a Mac awake during local AI coding
sessions, including the closed-lid case where regular `caffeinate` assertions are
not enough.

## Product shape

- Native macOS menu bar app with a status icon and optional active countdown.
- Privileged helper daemon owns power-management changes.
- `dsmnctl` provides a local CLI contract for debugging and automation.
- Raycast extension acts as a remote control, similar to Coffee-style duration
  commands.

## Safety rule

Only the helper daemon may apply:

```sh
pmset -a disablesleep 1
```

Every activation must have automatic release conditions. Raycast and the app only
send intent; they never modify system sleep settings directly.

## Current status

This repository currently contains a working signed macOS app stack:

- SwiftPM package
- core state and decision engine
- `dsmnctl` CLI, which tries the helper XPC service before falling back to local
  development state
- `dsmnctl install-hooks`, which installs the shared agent hook for Claude Code,
  Codex, Grok Build, and Pi
- `dsmnd` LaunchDaemon executable with an XPC Mach service
- Xcode-built `dsmn.app` that embeds the signed helper and LaunchDaemon plist
- menu bar controls for helper registration through `SMAppService`
- last-request visibility in the menu and CLI, including agent/session context
  when hooks provide it
- `Why Awake?` diagnostics that separate dsmn's lock from external macOS sleep
  assertions owned by apps such as Codex, Claude, or browsers
- Raycast extension for manual duration, stop, status, and menu bar
- Developer ID archive and notarization scripts
- Sparkle-based self-update integration for signed builds

The current local distributable is exported at `dist/export/dsmn.app`; the
notarized zip is written to `dist/dsmn-notarized.zip`.

## Local development

```sh
swift test
swift run dsmn-app
swift run dsmnctl status --json
swift run dsmnctl manual --minutes 30 --requester Terminal
swift run dsmnctl stop
swift run dsmnd
swift run dsmnd daemon-once
./script/build_and_run.sh
```

The Xcode project is generated from `project.yml`:

```sh
xcodegen generate
xcodebuild -project dsmn.xcodeproj -scheme dsmn -configuration Debug build
```

Distribution build:

```sh
./scripts/publish_release.sh
```

`publish_release.sh` archives the app, verifies Sparkle metadata, notarizes and
staples the bundle, creates a versioned Sparkle zip, generates a signed appcast,
uploads the release through the `dsmn-website` Railway service, and checks the
public appcast/download URLs.

Use `DSMN_STATE_DIR` to avoid writing to the default state directory while testing:

```sh
DSMN_STATE_DIR=/tmp/dsmn-dev swift run dsmnctl status
```

The one-shot `dsmnd` development command does not execute `pmset` unless
explicitly enabled:

```sh
DSMN_APPLY_PMSET=1 swift run dsmnd
```

The LaunchDaemon `serve` mode is intended to run as root from `SMAppService`.
Set `DSMN_APPLY_PMSET=0` to force dry-run behavior while debugging the helper.

## Documentation

- `AGENTS.md`
- `docs/ARCHITECTURE.md`
- `docs/SAFETY.md`
- `docs/RAYCAST.md`
- `docs/MACOS_APP.md`
- `docs/PACKAGING.md`
- `docs/HOOKS.md`
