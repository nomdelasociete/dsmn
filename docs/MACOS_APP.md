# macOS App

`dsmn` is the current Xcode-hosted macOS menu bar app. `dsmn-app` remains
available as a SwiftPM development entrypoint.

It is intentionally menu-bar-only, with no Dock icon. Clicking the pixel
heartbeat opens a compact native SwiftUI panel with a live countdown, power
lock state, last requester, recent activity, and timer controls.

The identity follows [website PR #5](https://github.com/nomdelasociete/dsmn-website/pull/5):
warm paper, charcoal, sage, orange warnings, and Geist Pixel headings. Window
colors follow the macOS appearance; the compact timer panel uses the website's
charcoal preview palette in both appearances. Controls retain system text and
diagnostics use IBM Plex Mono. Font licenses are bundled with the app.

The menu bar icon changes by state:

- heartbeat: off or loading;
- heartbeat with a steady activity pixel: a manual timer is active; a brief
  stepped scan repeats every 4.8 seconds while the helper confirms protection;
- warning triangle: status unavailable, fallback protection, incomplete setup,
  or a sleep lock that the helper has not applied.

The mark is a 22 × 16 pt template image for native menu bar sizing and contrast.
Every scan frame has the same dimensions, keeping the countdown steady. Scanning
stops when the timer expires, protection is unavailable, or Reduce Motion is
enabled; the activity pixel remains a static state cue. Animation sleeps between
scans and reuses cached images instead of running a continuous display timer.

## Panel and settings

| Surface | Actions and information |
|---------|-------------------------|
| Compact panel | Status, live countdown, power lock, last requester, 12-hour activity, 30m / 90m / Custom, Stop, Refresh, Setup, Why Awake, About, Quit |
| Setup & Troubleshooting | Helper install/update/approval/repair, agent hooks, launch at login, Doctor, Repair, countdown preference, software updates, feedback, Setup Guide |
| About | Version, credits, website, and confirmed removal of agent hooks |

Actions remain direct buttons; there are no nested SwiftUI menus. Stop remains
available even when helper registration is unavailable. Shortcuts are preserved:
⌘3 / ⌘9 for timers, ⌘. for Stop, ⌘R for Refresh, and ⌘Q for Quit.
Custom duration uses the existing floating native alert and accepts 1–720 minutes.

**Show countdown in menu bar** and **Launch at Login** live in the setup window.
Launch at Login uses `SMAppService.mainApp` and may require approval in System
Settings > General > Login Items.

See [design reference and validation](DESIGN.md) for asset provenance and previews.

## First-run setup

On first launch, dsmn opens a setup guide window. It exposes the same setup
actions as the menu:

- install the privileged helper;
- open Login Items when macOS requires approval;
- install agent hooks for Claude Code, Cursor, Codex, Grok Build, and Pi;
- optionally enable `Launch at Login`.

The guide can be reopened from **Setup & Troubleshooting... → Setup Guide**.

### Skip, Done, and incomplete setup

- **Skip for Now** or closing the window dismisses the wizard (`onboardingWizardDismissed`)
  but does **not** mean setup is healthy. The menu keeps a **Setup** warning plus
  **Setup & Troubleshooting...** until the helper is enabled and hooks report
  ready.
- **Done** / **Finish Later** when helper or hooks are still incomplete shows a
  confirmation, then dismisses the wizard the same way as Skip. Setup reminders stay
  in the menu.
- **Status** shows `Setup incomplete` after the wizard was dismissed while helper or
  hooks are still missing. The menu bar icon uses the warning state in that case.
- **Hide Setup Reminders** hides setup warning attention while setup is still
  incomplete. Helper/hook actions remain available from **Setup &
  Troubleshooting...**.

The important readiness signal is `Power lock`, not music playback or the
screen state. `Power lock: on` means dsmn successfully owns the macOS
`disablesleep` setting through its privileged helper. macOS exposes the live
system value as `SleepDisabled 1` in `pmset -g live`.

1. Launch the archived `dsmn.app`.
2. Open the menu bar icon.
3. Open **Setup & Troubleshooting...**, then **Install Helper** when required.
4. If needed, click **Approve Helper in Login Items**, enable dsmn in System
   Settings, then **Refresh** in the setup window.
5. Install agent hooks from the same setup area. Setup is ready when the helper
   is enabled and hooks report ready.

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

- `Keeping Mac awake` and a running countdown
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
dsmnctl doctor
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
Stop & Quit waits for the helper to confirm that its timer and owned power lock
are cleared. Failed or unconfirmed stops keep the app open with an error, even
if local timer cleanup succeeded. Retry Stop & Quit or explicitly choose Quit,
Keep Running; Cancel leaves the app running without issuing Stop. Stop remains
available when helper registration is missing or ambiguous.
Quitting the menu bar app alone does not unload the privileged helper and does
not disable installed agent hooks. A later Claude, Cursor, Codex, Grok, or Pi hook can
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
