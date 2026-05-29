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
dsmnctl auto on
dsmnctl auto off
dsmnctl auto toggle
dsmnctl stop
dsmnctl repair
```

## Helper

`dsmnd` will become a privileged LaunchDaemon registered through the app with
`SMAppService`. It is the only component allowed to call `pmset`.

The helper must:

- apply `pmset -a disablesleep 1` only when the decision engine says active;
- release with `pmset -a disablesleep 0` when no longer needed;
- persist ownership so recovery is possible after crash or reboot;
- expose status to the app and CLI.

Today `dsmnd` runs the same reconciliation path but defaults to dry-run power
operations. It only executes `pmset` when `DSMN_APPLY_PMSET=1` is present.

## App

`dsmn.app` will be a SwiftUI menu bar app.

The macOS menu bar item is icon-only. The icon should use an official SF Symbol
for the menu bar if a good one fits. App and Raycast branding must not use an SF
Symbol as a logo.

The current development entrypoint is `swift run dsmn-app`. It is a SwiftPM-hosted
menu-bar app that writes `dsmn` state but does not install or communicate with the
future privileged helper yet.

The Xcode entrypoint is generated from `project.yml` with XcodeGen. It builds:

- `dsmn.app`
- `DSMNCore.framework`
- `dsmnd`
- `dsmnctl`

## Raycast

The Raycast extension is a remote control. It invokes `dsmnctl` or the app URL
scheme. It never runs `sudo`, `pmset`, or `caffeinate`.
