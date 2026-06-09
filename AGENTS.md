# dsmn Agent Notes

## Operating Rules

- Always run `git fetch --all --prune` and check `git status --short --branch`
  before changing code.
- **Never commit or push directly to `main`.** Work on a feature branch, push
  the branch, and open a PR (`gh pr create`). Link the GitHub issue in the PR
  body (`Closes #N`). If you committed on local `main` by mistake: create a
  branch at that commit, `git reset --hard origin/main` on `main`, push only the
  branch.
- Keep changes scoped and commit/push each completed step (on the feature
  branch).
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
  - `DoctorReportFormatter` — shared human-readable doctor text for `dsmnctl`
    and the menu bar Doctor window.
  - `AgentHookLogInspector` — reads `DSMN_HOOK_LOG` for fallback-caffeinate
    warnings (doctor + menu).
- `Sources/dsmnapp`: SwiftUI menu bar app and helper registration UI.
  - `DoctorWindowPresenter`, `RepairResultPresenter`, `DSMNDoctorView` — menu
    and onboarding troubleshooting; call helper XPC via `HelperServiceClient`.
- `Sources/dsmnd`: privileged helper daemon and XPC service.
- `Sources/dsmnctl`: CLI used by the app, hooks, Raycast, and debugging.
- `raycast`: Raycast remote-control extension.
- `docs`: architecture, safety, hooks, Raycast, macOS app, and packaging notes.

## Supported Agents

`dsmnctl install-hooks` and `dsmnctl uninstall-hooks` support:

- Claude Code
- Codex
- Grok Build
- Pi

Full uninstall (`all` or no target) also removes `~/.dsmn/dsmn-agent-hook.sh`.
The menu exposes full uninstall from **About dsmn → Remove Agent Hooks…** (not a
top-level menu item).

All installed hooks call the shared script:

```sh
~/.dsmn/dsmn-agent-hook.sh
```

The script calls `dsmnctl manual --minutes 20 --extend-only --requester <agent>`
by default, records the last requester when possible, and falls back to
`caffeinate -is -t 600` only if `dsmnctl` or the helper is unavailable.

## Product Semantics (Do Not Regress)

These behaviors were corrected after the P1 quick-win PRs; treat GitHub issue
wording literally and verify against `main` before changing them.

### Manual timer and `pmset`

While `manualUntil > now`, `PowerDecisionEngine.shouldPreventSleepForManual`
returns **true** regardless of lid state. An open lid does **not** release the
macOS sleep lock while the manual timer is still running. The `lid_open_grace`
reason is informational only; it is not a release condition in
`docs/SAFETY.md`.

Do not reintroduce `lid_open_grace_elapsed` as a `stopReason` without an
explicit product decision.

The helper must not rely only on a periodic poll to release
`pmset disablesleep`. Every successful helper reconcile that leaves dsmn owning
the power lock must arm a one-shot release deadline for the earliest safety
deadline (`manualUntil`, or no-route grace expiry when earlier). Keep
`HelperXPCServiceSchedulerTests` covering: command arms the lock, no further
command arrives, the helper still calls `pmset disablesleep 0` and clears
state after expiry.

### Hook throttling

Throttle **`dsmnctl manual` calls**, not agent hook events. The installer must
keep firing hooks on `SessionStart`, `UserPromptSubmit`, `PreToolUse`, and
`PostToolUse` (and Pi’s extended events). The shared script skips `manual` when
`~/.dsmn/last-extend.stamp` is newer than `DSMN_HOOK_MIN_INTERVAL_SECONDS`
(default 120). See `docs/HOOKS.md`.

Wrong approach: removing `PreToolUse` / `PostToolUse` from
`AgentHookInstaller.hookEventNames` to reduce load.

### Hook uninstall (#17 / PR #55)

`AgentHookInstaller.uninstall` is symmetric to `install` for Claude/Codex JSON,
Grok `dsmn.json`, Pi `dsmn.ts`, and (on full uninstall) `~/.dsmn/dsmn-agent-hook.sh`.

- **Per-hook removal inside groups** — Claude/Codex events can share one JSON
  group with a `matcher` and multiple `hooks` entries (for example dsmn beside
  `safety.sh`). Uninstall must filter individual `hooks[]` commands, not drop the
  whole group. Wrong: `groups.filter { !isDsmnHookGroup($0) }`. Right: compactMap
  each group, filter `group["hooks"]` with `isDsmnHook`, keep the group when
  non-dsmn hooks remain.
- **Do not revert Codex `features.hooks`** on uninstall; only edit
  `~/.codex/hooks.json`.
- **UI placement** — full uninstall lives under **About dsmn → Remove Agent
  Hooks…** with a second confirmation alert, not a top-level menu row.
- **Idempotent** — second `uninstall-hooks` reports `not installed` / `not present`.

### Hook fallback vs protected

`caffeinate` fallback does not provide closed-lid protection. When
`AgentHookLogInspector` reports active fallback, doctor and menu must warn
distinctly from normal `Active` + `Power lock: on`.

### Menu bar menu structure

Do not put nested SwiftUI `Menu` controls inside `DSMNMenuView`'s
`MenuBarExtra` content. In practice those submenus can flicker, dismiss before
clicks land, or make actions appear inert. Keep menu bar actions as direct
top-level rows grouped by `Section`. The **Setup & Troubleshooting...** menu
item must be a direct button that opens `SetupTroubleshootingWindowPresenter`,
not a nested menu. Put helper, hook, repair, and setup-guide actions in that
dedicated window.

### Helper updates after app updates

Normal app updates can leave the privileged helper running the previous parent
bundle build until the user chooses **Update Helper**. Treat that state as
advisory, not broken:

- Do not mark setup incomplete only because `helperNeedsUpdate` is true while
  the helper is enabled and responding.
- Do not switch the menu bar icon to warning for ordinary helper version drift.
- Do not hide trigger activity or block manual timer commands because of helper
  version drift.
- Surface it as **Helper update available** with an explicit **Update Helper**
  action and a **Later** path for the current app build.

`helperNeedsRepair`, missing helper registration, and Login Items approval are
still blocking setup states. If a future helper protocol change truly requires
an immediate helper update, add a separate required-update state and tests
instead of reusing ordinary version drift.

## Build And Test

Use these checks for normal changes — **all four are required before opening a
PR**, not only `swift test`:

```sh
swift test
xcodegen generate
xcodebuild -project dsmn.xcodeproj -scheme dsmn -configuration Debug -destination 'platform=macOS' -derivedDataPath DerivedData build
./scripts/verify_bundle.sh DerivedData/Build/Products/Debug/dsmn.app
```

For menu bar interaction changes, also run:

```sh
./scripts/e2e_menu_setup.sh
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

- `Status: active` means a bounded manual timer is running. With
  `Status source: helper`, expect `Power lock: on` and `macOS SleepDisabled: on`
  for the whole timer, including when the lid is open. If the timer is active
  but the lock is off, check `doctor` for `Hook fallback: active` or
  `Status source: local fallback` before changing hook or detection logic.

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

## macOS Menu Bar Menu (`MenuBarExtra`)

`DSMNMenuView` is grouped into **Status**, **Control**, **Setup**, and **More**
(see `MenuBarMenuPresentation.swift`). Presentation rules live on
`DSMNMenuStore`; the view should stay layout-only.

Rules learned from shipping #9:

- **Static status text** — use plain `Label` rows in menu sections. Do not wrap
  status copy in `Button { }` with `.disabled(true)`; that breaks macOS menu
  highlighting, keyboard navigation, and submenu behavior.
- **Stop is always available** — do not gate **Stop** on `canRunAwakeCommands`.
  Users must be able to release a timer even when the helper is missing or
  mid-registration; only **Keep Awake** actions use `canRunAwakeCommands`.
- **Custom duration** — lives in **Control** via `NSAlert` + `NSTextField`
  (1–720 minutes, floating window). Match `SafetyPolicy.maxManualDurationMinutes`
  if that policy becomes persisted (#38).
- **Sparkle** — menu takes `SoftwareUpdateController?` and uses
  `CheckForUpdatesView(updateController:)`, not a raw `SPUUpdater`.
- **Manual test required** — `swift test` does not exercise `MenuBarExtra` menus.
  After menu changes, open the live menu: status glance, Stop while helper
  unregistered, nested **Setup & Troubleshooting** and **Diagnostics**, shortcuts
  ⌘3 / ⌘9 / ⌘. / ⌘R / ⌘Q.

## Agent Workflow

- After the maintainer merges and publishes, `git pull` on `main` and read
  post-merge fix commits before starting new work. For #17, PR #55 shipped
  uninstall-hooks; commit `94f0d87` fixed mixed hook groups (do not regress).
- When an issue asks for a “menu action”, prefer a low-traffic surface (About,
  Setup submenu) unless the action is daily-use — #17 used About, not More menu.
- Parallel issue branches in separate worktrees are fine; expect merge
  conflicts in `DSMNMenuStore.swift` when multiple menu PRs land together.
- Prefer shared logic in `DSMNCore` (formatter/inspector) over duplicating CLI
  text in the app.
- UI work that adds onboarding steps: use `ScrollView` and verify the window
  size in `OnboardingWindowPresenter` (currently 720×720).
- When changing `PowerDecisionEngine` or hook scripts, update `docs/SAFETY.md`
  and `docs/HOOKS.md` in the same PR.
- Current shipped baseline: **0.1.22**, **87** `swift test` cases on `main`
  (includes #17 uninstall-hooks + mixed-group fix).

## Safety Notes

- Hooks create bounded manual leases; the hook script may run on every tool
  event but throttles `dsmnctl manual` to at most once per minimum interval.
- Hooks record the last requester, for example `Codex - dsmn - session abc12345`
  when the hook payload exposes session context.
- Long-lived agent processes alone do not keep the Mac awake; dsmn only stays
  active while a manual timer is still valid.
- dsmn does not intentionally keep the display awake.
