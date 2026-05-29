# Architecture

`dsmn` is split into four layers.

## Core

`DSMNCore` contains value models, agent detection, state persistence, and the
decision engine. It has no UI and does not directly mutate power settings.
System facts such as battery, default route, and lid state are read through an
injectable snapshot provider so the daemon can be tested without depending on the
live machine state.

The effective state is:

```text
manualActive = manualUntil > now
autoActive = autoEnabled && detectedAgents.count > 0
effectiveActive = (manualActive || autoActive) && safetyOK
```

## CLI

`dsmnctl` is the stable automation contract used by Raycast, scripts, and manual
debugging.

Planned stable commands:

```sh
dsmnctl status --json
dsmnctl manual --minutes 90
dsmnctl manual --minutes 20 --extend-only
dsmnctl auto on
dsmnctl auto off
dsmnctl auto toggle
dsmnctl stop
dsmnctl repair
```

## Helper

`dsmnd` is the privileged LaunchDaemon executable registered through the app with
`SMAppService`. It is the only component allowed to call `pmset`.

The helper must:

- apply `pmset -a disablesleep 1` only when the decision engine says active;
- release with `pmset -a disablesleep 0` when no longer needed;
- persist ownership so recovery is possible after crash or reboot;
- expose status to the app and CLI over the Mach service
  `com.nomdelasociete.dsmn.helper`.

The development one-shot command runs the same reconciliation path but defaults
to dry-run power operations. The LaunchDaemon `serve` mode executes power changes
only when running as root, unless `DSMN_APPLY_PMSET=0` forces dry-run mode.

The daemon owns system state in `/Library/Application Support/dsmn`. User-facing
local development state remains under `~/.dsmn` unless `DSMN_STATE_DIR` is set.
In LaunchDaemon `serve` mode, the daemon reconciles immediately at startup and
then every 30 seconds so auto mode follows agent processes without a menu or
Raycast command having to run.

## App

`dsmn.app` is a SwiftUI menu bar app.

The macOS menu bar item is icon-only. The icon should use an official SF Symbol
for the menu bar if a good one fits. App and Raycast branding must not use an SF
Symbol as a logo.

The current development entrypoint is `swift run dsmn-app`. The Xcode-built app
embeds:

- `Contents/Library/LaunchDaemons/dsmnd`
- `Contents/Library/LaunchDaemons/com.nomdelasociete.dsmn.helper.plist`

It can register or unregister the helper with `SMAppService.daemon(plistName:)`.
For local development before approval/notarization, it falls back to local state
when the helper is not registered.

The Xcode entrypoint is generated from `project.yml` with XcodeGen. It builds:

- `dsmn.app`
- `DSMNCore.framework`
- `dsmnd`
- `dsmnctl`

## Raycast

The Raycast extension is a remote control. It invokes `dsmnctl`. `dsmnctl` tries
the helper XPC service first and falls back to local state for development. It
never runs `sudo`, `pmset`, or `caffeinate`.
