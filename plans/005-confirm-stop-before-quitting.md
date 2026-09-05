# Plan 005: Keep the app open when Stop & Quit cannot confirm a stop

> Executor: Start with `git fetch --all --prune`, `git status --short --branch`,
> and `git diff --stat 513b03a..HEAD -- Sources/dsmnapp Sources/DSMNCore/HelperXPC.swift Tests Package.swift docs/SAFETY.md docs/MACOS_APP.md`.
> Check the excerpts against current source. Prerequisite changes from Plans
> 001/002/004 are expected; preserve their behavior. Run from your checkout root.

## Status

- Priority: P1
- Effort: M
- Risk: LOW–MED; narrow control-flow change with executable app tests
- Depends on: `001-preserve-failed-repair-ownership.md`
- Integration gate: combine with `002-release-despite-diagnostic-failures.md`
  before final validation; the app's injected Stop outcome interface can be
  implemented independently while that helper work proceeds
- Ordering preference: after Plan 004, which adds the app test target and touches
  the same store/service files; Plan 004's legacy rollout decision does not block
  this fix if it must proceed first
- Category: bug
- Planned at: `513b03a`, 2026-09-05; audit finding 4
- Implementation status: IN PROGRESS

## Why this matters

The user explicitly choosing Stop & Quit expects dsmn to end its current timer
before closing. The store currently absorbs helper failures and may return local
fallback state; the view then terminates unconditionally. That removes the UI
while the privileged helper may still own a power lock. This plan makes the
termination decision depend on an explicit helper-confirmed stop outcome.

## Current state and conventions

`Sources/dsmnapp/Views/DSMNMenuView.swift:222`:

```swift
Task {
    await store.stopNow()
    NSApplication.shared.terminate(nil)
}
```

`Sources/dsmnapp/Stores/DSMNMenuStore.swift:510` returns no outcome:

```swift
func stopNow() async {
    await mutate(local: {
        try $0.stop()
    }, helper: {
        try await self.helper.stop()
    })
}
```

The generic `mutate` catches helper errors and runs the local operation. It also
skips helper access when `SMAppService` does not say enabled, even though
`readStatus` deliberately tries XPC because registration can be ambiguous across
app copies. A local state reset is not evidence that the root daemon stopped.

The helper can return a successful envelope whose status still has
`ownsSleepDisable == true` after a nonzero normal release result. Therefore an
await that did not throw is also insufficient evidence. Check the actual
returned ownership and manual intent.

App services and stores use `@MainActor`; inject small asynchronous operations
for tests. Plans 001/002 provide typed helper command errors and bounded reliable
Stop processing. Plan 004 introduces a `dsmnappTests` executable-test target; if
this plan runs before it, add the target using the existing `dsmndTests` pattern
in `Package.swift`.

Product constraints from `docs/SAFETY.md`: quitting alone leaves the helper and
hooks running. Preserve the explicit Quit, Keep Running choice. Hooks may start
a new timer after a successful Stop; this action is not a persistent pause.
Stop remains available even if registration is missing or in progress. Keep
direct top-level menu rows and existing keyboard shortcuts.

## Scope

Only modify:

- `Sources/dsmnapp/Stores/DSMNMenuStore.swift`
- `Sources/dsmnapp/Services/HelperServiceClient.swift` if a narrow stop seam is
  needed; preserve Plan 004's lifecycle methods
- New `Sources/dsmnapp/Services/AppQuitCoordinator.swift`
- `Sources/dsmnapp/Views/DSMNMenuView.swift`
- `Sources/dsmnapp/Views/WhyAwakeView.swift` for its existing `stopNow` call only
- New `Tests/dsmnappTests/StopOutcomeTests.swift` and
  `Tests/dsmnappTests/AppQuitCoordinatorTests.swift`
- `Package.swift` only if the app test target has not already been added
- `docs/SAFETY.md`, `docs/MACOS_APP.md`
- This plan/index and necessary generated `dsmn.xcodeproj/project.pbxproj` changes

Do not change normal manual-command fallback, CLI output, Raycast, hook events,
automatic setup prompting, helper version advisory semantics, power policy, or
the user's ability to select Quit, Keep Running. A persistent pause feature is
separate product work.

## Steps and verification

### 1. Make a stop outcome testable

Add a narrow stop request injection to the store or extract its stop orchestration
into the new app service. Keep production `DSMNMenuStore()` construction intact.
Tests must use a temporary local controller and avoid production preference
migration, real XPC, or Login Items writes. Add an internal test initializer or
injected initialization closure rather than mocking every store dependency.

Define a typed result that distinguishes helper-confirmed stop, local-only cleanup,
and failure/unconfirmed result. A confirmed stop requires a response from the
authenticated helper with no manual timer and `ownsSleepDisable == false`.
Confirmation concerns dsmn's lock and lease; it is not a claim that other apps
have no macOS sleep assertions.

Verify: `swift test --filter StopOutcomeTests` executes at least the success,
helper-error, local-only, still-owned, and still-armed fixtures. Add regression
assertions that fail on the old behavior before implementing the new routing.

### 2. Return truthful stop results

Give `stopNow` the explicit result type and stop routing it through the generic
fire-and-forget `mutate` path. Attempt the helper operation even when registration
status is ambiguous; a responding authenticated helper is authoritative. On
transport failure, optional local cleanup remains useful, but its outcome is
local-only and never eligible for Stop & Quit confirmation. Preserve the helper
error rather than overwriting it with a successful local report.

For nonzero release results represented by a still-owned response, invalid
responses, a still-armed timer, or timeouts, return an unconfirmed/failure result.
Update the regular `stop()` button wrapper to consume the result and show truthful
feedback. Keep it enabled independently of `canRunAwakeCommands`. Use the existing
refreshing/error presentation without making unrelated store operations serial.

Also update the Stop dsmn action in `WhyAwakeView.swift:152` to consume the new
outcome. It currently refreshes immediately after `stopNow`; that refresh must
not silently discard an unconfirmed-stop message. Keep this change limited to
the existing action and its failure feedback.

Verify: `swift test --filter StopOutcomeTests` exits zero. Cover misleading
registration status with a successful helper, unavailable helper plus successful
local cleanup, local cleanup failure, helper error, timeout, still-owned response,
still-armed response, and confirmed release. Each request must call the helper
at most once; a timed-out request is not silently retried as a new command.

### 3. Gate termination through an executable coordinator

Implement `AppQuitCoordinator` as a small main-actor service with injected stop,
terminate, and failure-presentation closures. Its Stop & Quit operation awaits the
typed result, invokes terminate exactly once only for a confirmed stop, and
otherwise presents a clear error while leaving the app running. Route the
existing first alert button through it. The user can retry or explicitly choose
Quit, Keep Running through the existing flow.

Leave the other alert branches intact: Quit, Keep Running closes without issuing
Stop, and Cancel does neither. Prevent duplicate termination from repeated
in-flight Stop & Quit requests. Keep the existing text that future hooks may
start a new timer after successful Stop.

Verify: `swift test --filter AppQuitCoordinatorTests` exits zero. Assert actual
closure invocation counts and ordering for success, thrown/failed/local-only
outcomes, a delayed response, and duplicate in-flight requests. Do not call
`NSApplication.terminate` in tests or replace these tests with source searches.

### 4. Validate the user path and documentation

Update the quit behavior in safety/app documentation: failed confirmation keeps
the app open, local cleanup does not prove a system stop, and explicit keep-running
quit remains available. Run all gates below. In a controlled UI test session,
verify the alert and error copy with a failing injected helper; keep the real
installed helper registered during automated tests.

Verify: `swift test` and `./scripts/e2e_menu_setup.sh` exit zero, and record the
targeted Stop & Quit interaction result. The existing menu script is a structural
smoke check, not proof of this new failure behavior; the closure-based app tests
provide its automated regression evidence.

## Commands and done criteria

| Command | Required result |
| --- | --- |
| `swift test` | All tests pass, including new executable app tests |
| `xcodegen generate` | Exit zero |
| `xcodebuild -project dsmn.xcodeproj -scheme dsmn -configuration Debug -destination 'platform=macOS' -derivedDataPath DerivedData build` | BUILD SUCCEEDED |
| `./scripts/verify_bundle.sh DerivedData/Build/Products/Debug/dsmn.app` | Exit zero |
| `./scripts/e2e_menu_setup.sh` | Exit zero |
| `git diff --check` | Exit zero |
| `git diff --name-only` | Only scoped files |

- [ ] Every unconfirmed stop outcome leaves termination count at zero.
- [ ] Confirmed stop terminates once, after the helper response.
- [ ] Local-only cleanup cannot erase the error or count as helper confirmation.
- [ ] Stop is available with missing/ambiguous registration.
- [ ] Quit, Keep Running, Cancel, shortcuts, and direct menu structure are intact.
- [ ] Tests leave user preferences, live helper registration, and power unchanged.
- [ ] Standard and targeted UI checks are recorded in the PR and plan index.

## Git and release workflow

Use feature branch `jb/confirm-stop-before-quit`, updated from main containing its
prerequisites. Commit and push completed logical steps on the feature branch;
never commit or push main. Open a PR after checks pass and link its real GitHub
issue with `Closes #N`; resolve the issue association before PR creation. Match
imperative subjects such as "Keep dsmn open when Stop & Quit fails".

After an authorized merge, release through `.claude/commands/release-dsmn.md`
and verify public artifacts. A release is not part of executing the unit tests
or this planning task.

## Stop conditions and maintenance

Report a scope decision if this requires redesigning global report provenance,
changing manual lease semantics, or disabling ordinary Stop while the helper is
unavailable. If app tests cannot import the executable target, resolve that
build-test boundary rather than moving AppKit into DSMNCore or returning to
source-string assertions. Keep stop confirmation distinct from persistent pause
and from helper retirement; later hooks are still allowed to create new leases.
