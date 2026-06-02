# macOS App

`dsmn` is the current Xcode-hosted macOS menu bar app. `dsmn-app` remains
available as a SwiftPM development entrypoint.

It is intentionally menu-bar-only:

- no Dock icon;
- status icon with an optional countdown while a manual lease is active;
- native crown logo for the menu bar status item;
- compact Coffee-style actions.

The menu bar icon changes by state:

- crown: off;
- crown reversed inside a circle: manual timer actively preventing sleep;
- `exclamationmark.triangle`: status unavailable, or dsmn wants to prevent
  sleep but the helper has not applied the power lock.

The `Show Countdown` menu toggle controls whether active manual timers appear
next to the status icon.

The `Launch at Login` menu toggle asks macOS to launch `dsmn.app` when the user
logs in. It is optional and uses `SMAppService.mainApp`; macOS may ask for
approval in System Settings > General > Login Items.

## First-run setup

On first launch, dsmn opens a setup guide window. It exposes the same setup
actions as the menu:

- install the privileged helper;
- open Login Items when macOS requires approval;
- install agent hooks for Claude Code, Codex, Grok Build, and Pi;
- optionally enable `Launch at Login`.

The guide can be reopened from `Setup Guide` in the menu bar menu.

The important readiness signal is `Power lock`, not music playback or the
screen state. `Power lock: on` means dsmn successfully owns the macOS
`disablesleep` setting through its privileged helper. macOS exposes the live
system value as `SleepDisabled 1` in `pmset -g live`.

1. Launch the archived `dsmn.app`.
2. Open the menu bar icon.
3. If the menu says `Setup: install helper`, click `1. Install Helper`.
4. If the menu says `Setup: approve Login Items`, click `2. Open Login Items`,
   enable dsmn in System Settings, then return to the menu and click `Refresh`.
5. Setup is ready when the menu says `Helper: enabled`.

When dsmn is idle, `Power lock: off` is expected. It should switch to
`Power lock: on` only while a manual timer is active.

## Test protocol

Use a timestamp log instead of music playback. Some apps pause audio when the
lid closes even if the Mac stays awake.

Start a visible heartbeat:

```sh
rm -f /tmp/dsmn-ticks.log
while true; do date '+%Y-%m-%d %H:%M:%S'; sleep 5; done | tee /tmp/dsmn-ticks.log
```

For the deterministic test, click `Keep Awake 30m` in the dsmn menu. Wait for:

- `Active - 30m`
- `Helper: enabled`
- `Power lock: on`

Then unplug the Mac, close the lid for 60-90 seconds, reopen it, and check:

```sh
tail -n 30 /tmp/dsmn-ticks.log
```

If timestamps continued every five seconds while the lid was closed, dsmn kept
the Mac awake. A large timestamp gap means the machine slept.

You can also inspect the current state from the archived app bundle:

```sh
/Users/jb/Documents/Github/NomDeLaSociete/dsmn/dist/export/dsmn.app/Contents/Library/Helpers/dsmnctl doctor
pmset -g live | rg 'SleepDisabled'
```

## Why Awake

The `Why Awake?` menu action opens a diagnostic window. It separates:

- dsmn state: timer, power lock ownership, and last requester;
- macOS state: live `SleepDisabled`, sleep line, and display sleep line;
- external assertions from `pmset -g assertions`, grouped into system sleep,
  display sleep, and other blockers.

This is intentionally different from `dsmnctl doctor`: `doctor` answers whether
dsmn is healthy, while `Why Awake?` answers why macOS currently thinks the Mac
should stay awake.

## Run locally

```sh
swift run dsmn-app
```

For the Xcode-built `.app` bundle:

```sh
./script/build_and_run.sh
```

The app writes state through `DSMNCore` in development mode. In the Xcode-built
bundle, it also embeds the helper executable and LaunchDaemon plist and can ask
`SMAppService` to register or unregister the helper.

## Menu actions

- `Keep Awake 30m`
- `Keep Awake 90m`
- `Show Countdown`
- `Launch at Login`
- `Check for Updates...`
- `Why Awake?`
- `Setup Guide`
- `Stop`
- `Refresh`
- `1. Install Helper`
- `2. Open Login Items`
- `Unregister Helper`
- `Quit`

If dsmn is active, `Quit` asks whether to `Stop & Quit` or `Quit, Keep Running`.
Quitting the menu bar app alone does not unload the privileged helper and does
not disable installed agent hooks. A later Claude, Codex, Grok, or Pi hook can
start a fresh manual timer again.

## Next bundle step

The production app is packaged as `dsmn.app` with:

- `LSUIElement` enabled;
- helper registration through `SMAppService`;
- optional launch-at-login registration through `SMAppService.mainApp`;
- signed helper embedded in the app bundle;
- final app icon asset separate from SF Symbols.

Still required for a production install:

- copy the archived app to `/Applications`;
- notarize the app before relying on LaunchDaemon registration;
- approve the helper in System Settings when macOS requests it.

## Xcode project

`project.yml` is the source of truth for the Xcode project. Regenerate with:

```sh
xcodegen generate
```

The detected Apple Development team is `JSFMAD28GS` for `NOM DE LA SOCIETE`.
The generated Debug app is signed with the local Apple Development certificate.
