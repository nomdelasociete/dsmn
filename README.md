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

This repository currently contains the foundation:

- SwiftPM package
- core state and decision engine
- `dsmnctl` dry-run CLI
- `dsmnd` daemon runner with dry-run `pmset` operations by default
- Raycast extension scaffold

The privileged helper and signed macOS app bundle are the next milestone.

## Local development

```sh
swift test
swift run dsmn-app
swift run dsmnctl status --json
swift run dsmnctl manual --minutes 30
swift run dsmnctl auto toggle
swift run dsmnctl stop
swift run dsmnd
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

`dsmnd` does not execute `pmset` unless explicitly enabled:

```sh
DSMN_APPLY_PMSET=1 swift run dsmnd
```

That command is intended for the future privileged helper context, not ordinary
Raycast execution.
