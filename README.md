# dsmn

`dsmn` means "don't stop me now".

It is a macOS utility for intentionally keeping a Mac awake during local AI coding
sessions, including the closed-lid case where regular `caffeinate` assertions are
not enough.

## Product shape

- Native macOS menu bar app with an icon-only menu bar item.
- Privileged helper daemon owns power-management changes.
- `dsmnctl` provides a local CLI contract for debugging and automation.
- Raycast extension acts as a remote control, similar to Coffee-style duration and
  toggle commands.

## Safety rule

Only the helper daemon may apply:

```sh
pmset -a disablesleep 1
```

Every activation must have automatic release conditions. Raycast and the app only
send intent; they never modify system sleep settings directly.

## Current status

This repository currently contains the foundation plus the first privileged
helper integration slice:

- SwiftPM package
- core state and decision engine
- `dsmnctl` CLI, which tries the helper XPC service before falling back to local
  development state
- `dsmnctl install-hooks`, which installs the shared agent hook for Claude Code,
  Codex, Grok Build, and Pi
- `dsmnd` LaunchDaemon executable with an XPC Mach service
- Xcode-built `dsmn.app` that embeds the signed helper and LaunchDaemon plist
- menu bar controls for helper registration through `SMAppService`
- Raycast extension scaffold

The remaining production milestone is packaging/notarization plus a real
installation pass from `/Applications`.

## Local development

```sh
swift test
swift run dsmn-app
swift run dsmnctl status --json
swift run dsmnctl manual --minutes 30
swift run dsmnctl auto toggle
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

- `docs/ARCHITECTURE.md`
- `docs/SAFETY.md`
- `docs/RAYCAST.md`
- `docs/MACOS_APP.md`
- `docs/PACKAGING.md`
- `docs/HOOKS.md`
