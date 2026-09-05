# Plan 002: Release expired and stopped leases despite diagnostic failures

> Executor: Follow the steps and gates below. Begin with `git fetch --all --prune`,
> `git status --short --branch`, and
> `git diff --stat 513b03a..HEAD -- Sources/DSMNCore Sources/dsmnd Tests docs/SAFETY.md docs/HOOKS.md`.
> Plan 001 is an expected source change: verify its ownership/error/retry
> guarantees instead of reverting them. Resolve other relevant drift before
> editing. Commands run from the executor's checkout root.

## Status

- Priority: P1
- Effort: L; separates safety work from optional telemetry and bounds processes
- Risk: MED
- Depends on: `001-preserve-failed-repair-ownership.md`
- Category: bug
- Planned at: `513b03a`, 2026-09-05; audit finding 5
- Implementation status: DONE; reviewed on 2026-09-05 (233 combined tests and all four standard gates passed)

## Why this matters

An expired timer is sufficient reason to release dsmn's owned lock. Today that
release first requires agent detection and every system probe to succeed. The
same synchronous probes run under the helper's operation lock, and the process
runner has no timeout. Consequently a diagnostic error can prevent release, and
a hung status request can block Stop and both timer mechanisms.

This plan makes a release attempt independent of optional diagnostics. It cannot
promise successful power changes when macOS rejects `pmset`; such failures must
retain ownership and retry using Plan 001's guarantees.

## Current state and conventions

`Sources/DSMNCore/StatusReport.swift:195`:

```swift
let originalState = try store.load()
let agents = try detector.detect(using: processListing)
let snapshot = try snapshotProvider.snapshot(now: now)
```

Only afterward does reconcile clear an expired `manualUntil`. Both `stop()` and
`enableManual()` also call the throwing `makeStatus` after persisting intent.
The helper chains these operations before reconciliation.

`Sources/DSMNCore/CommandRunner.swift:36`:

```swift
try process.run()
let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
process.waitUntilExit()
```

`Sources/dsmnd/HelperXPCService.swift:129` calls the live-state provider before
controller reconciliation, under `operationLock`. The default provider invokes
`SleepDiagnosticsInspector.report()`, which runs both `pmset -g live` and
`pmset -g assertions` even though this path needs only `SleepDisabled`.

The helper has a periodic timer and a separate one-shot release timer on the
same serial timer queue. Its `status` method also holds `operationLock` during
process listing and snapshots. A second timer does not bypass a blocked lock.

Use injected `CommandRunning`, `ProcessListing`, `SystemSnapshotProviding`, and
`PowerManaging` dependencies. Preserve the test style in
`Tests/dsmndTests/HelperXPCServiceSchedulerTests.swift`: a temporary state directory,
a locked recording power manager, and observed eventual state without a second
command. Use expectations or a controllable scheduler for new timing cases;
keep the existing real one-shot timer regression.

Product constraints from `docs/ARCHITECTURE.md` and `docs/SAFETY.md`: process
presence is diagnostic only; manual leases drive protection. The earliest
manual expiry or known no-route grace deadline releases the owned lock. An open
lid never terminates an otherwise safe active timer. After a successful release,
request `sleepnow` only with confirmed closed lid and battery power. Unknown
facts are not false, AC, or a closed lid.

## Scope

Only modify:

- `Sources/DSMNCore/CommandRunner.swift`, `StateStore.swift`, `StatusReport.swift`,
  `SystemSnapshotProvider.swift`, `SleepDiagnosticsInspector.swift`,
  `ReconcileSchedule.swift`, `HelperXPC.swift`, `Models.swift`, and
  `PowerDecisionEngine.swift`, and `AgentDetector.swift` (route `PSProcessListing`
  through the bounded command runner; its previous private `Process` bypasses it)
- New `Sources/DSMNCore/ControllerTelemetry.swift` for immutable observations
- `Sources/dsmnd/HelperXPCService.swift`
- New `Tests/DSMNCoreTests/CommandRunnerTests.swift`
- `Tests/DSMNCoreTests/AgentDetectorTests.swift` for process-list runner fixtures
- `Tests/DSMNCoreTests/DaemonReconcileTests.swift`, `RepairTests.swift`,
  `SystemSnapshotProviderTests.swift`, `ReconcileScheduleTests.swift`,
  `PowerDecisionEngineTests.swift`
- `Tests/dsmndTests/HelperXPCServiceSchedulerTests.swift`
- `docs/SAFETY.md`, `docs/HOOKS.md`; this plan and its index row
- `dsmn.xcodeproj/project.pbxproj` only for necessary XcodeGen output

Allow a new narrowly scoped core telemetry/snapshot value file if separating the
existing protocols requires it; record its exact name in this scope before
creating it. No policy-threshold changes, agent-event removals, XPC auth changes,
app redesign, general state-store recovery, or hook-script optimization.

## Steps and verification

### 1. Capture release independence as regression tests

Use throwing process-listing and snapshot fixtures. Test expired and explicitly
stopped owned leases with each fixture failing separately and together. A power
release attempt must still occur and, if successful, clear ownership. Test that
diagnostic failure after intent persistence cannot prevent helper reconciliation.
Keep a known no-route deadline test: unknown fresh route information must not
erase a previously recorded deadline; only a confirmed route restoration may
reset it.

Verify: `swift test --filter 'DaemonReconcileTests|HelperXPCServiceSchedulerTests'`
fails on the new assertions against the pre-fix behavior. Existing successful
power-operation and expiry tests must remain present.

### 2. Bound real subprocess execution

Give `ProcessCommandRunner` a configurable finite timeout with a two-second
default. Concurrently drain both pipes. On timeout, terminate the process this
runner created, allow a short bounded grace, then force termination if needed;
reap it and close handles. Return a distinguishable timeout error. A detached
task that leaves the original blocking process alive is not a timeout solution.
Keep executable paths and argument arrays separate, with no shell interpolation
in production callers.

Test actual harmless children: a successful command, nonzero exit, simultaneous
stdout/stderr output larger than pipe capacity, a sleeping child, and repeated
timeouts. Override the timeout to tens of milliseconds for tests; permit generous
scheduling tolerance and assert no child survives cleanup. Do not invoke real
power mutations in tests.

Verify: `swift test --filter CommandRunnerTests` exits zero, large-output results
are complete, and timeout cases finish within their bounded test expectations.

### 3. Separate mandatory release from optional enrichment

Split persisted intent/state work from status enrichment in `DSMNController`.
For owned locks with expired, absent, or explicitly stopped intent, attempt
release before agent listing, live ownership discovery, or optional diagnostics.
Reuse Plan 001's audited release operation. Do not require a full
`SleepDiagnosticsReport` to discover the single live lock flag on other paths.

After a successful mandatory release, gather bounded current power/lid facts for
the closed-lid battery follow-up. If either is unknown, omit `sleepnow`; preserve
the successful release. For normal decisions, collect snapshot fields
independently so a failed route probe does not discard a valid battery reading.
Represent unavailable fields as unknown and agent-list failure as unavailable
diagnostics; do not fabricate healthy readings.

Preserve source-compatible public controller entry points where feasible. Add
internal intent-only/report-from-facts functions rather than duplicating the
decision engine. Ensure `stop()` persistence is followed by release even if
forming a display report fails. Keep known no-route tracking intact on an
unknown sample. Do not change the documented treatment of unknown facts for
new activations as part of this fix.

Specifically, `DSMNState.updateNoRouteTracking` currently clears its timestamp
for an unknown route sample. Preserve that timestamp while a lease is active
until the route is confirmed restored. In `PowerDecisionEngine`, a previously
recorded no-route grace deadline remains enforceable when the next sample is
unknown. Unknown with no recorded outage must not invent a new outage. Cover
both cases and explicit route restoration in the existing engine tests.

Verify: `swift test --filter 'DaemonReconcileTests|RepairTests|SystemSnapshotProviderTests|PowerDecisionEngineTests'`
exits zero. Assert the recorded operation order; successful mandatory release
must precede optional diagnostics in fault-injection tests.

### 4. Keep helper scheduling and status responsive

Move optional telemetry collection out of the operation lock. Use a cached or
already-collected immutable snapshot for helper status; label its timestamp
honestly. Serialize only state/power changes and cache publication. Capture
nonmandatory telemetry outside the lock, then reload state and use the current
time inside the lock so a concurrent renewal is not overwritten by a stale
snapshot. Initial-cache failure must not block an owned lock's release.

On every mutation/reconcile error, use the state-based schedule from Plan 001 to
retain a bounded retry. A fired one-shot timer that encounters a thrown error
must rearm rather than disappear until the next periodic poll. Preserve the
earliest safety deadline and avoid a tight retry loop. If command-specific XPC
timeouts need adjustment to cover the finite release budget, change only Stop
and Repair and document the measured bound; leave hook event timeouts intact.

Add helper tests where a slow status probe overlaps expiry or Stop, a due timer
encounters one failure and later succeeds without another command, and renewal
arrives while telemetry is in flight. Assert no shortened lease, no lost stop,
and no blocking dependence on completing that status probe.

Verify: `swift test --filter 'HelperXPCServiceSchedulerTests|ReconcileScheduleTests'`
exits zero, including expiry without periodic polling. The overlap test must
prove the release occurs before the test unblocks the optional probe.

### 5. Document limits and run all gates

Explain mandatory cleanup, unknown telemetry, bounded command failure, and retry
behavior in `docs/SAFETY.md`; keep the hook lease description in `docs/HOOKS.md`
consistent. Distinguish a guaranteed bounded attempt from guaranteed OS success.

## Commands and done criteria

| Command | Required result |
| --- | --- |
| `swift test` | All tests pass, including Plan 001 regressions |
| `xcodegen generate` | Exit zero |
| `xcodebuild -project dsmn.xcodeproj -scheme dsmn -configuration Debug -destination 'platform=macOS' -derivedDataPath DerivedData build` | BUILD SUCCEEDED |
| `./scripts/verify_bundle.sh DerivedData/Build/Products/Debug/dsmn.app` | Exit zero |
| `git diff --check` | Exit zero |
| `git diff --name-only` | Only scoped files and necessary regenerated project changes |

- [x] Throwing diagnostics cannot prevent expired/stopped owned-lock release.
- [x] Real subprocess timeouts terminate and reap children; both pipes drain.
- [x] A blocked optional status probe cannot hold up deadline cleanup.
- [x] A failed timer callback retries without a new command or periodic poll.
- [x] Current manual/open-lid, no-route, and battery/lid follow-up semantics pass.
- [x] Index status and verification evidence are updated.

## Git workflow

Use a fresh feature worktree containing Plan 001, branch
`jb/release-despite-probe-failures`, and imperative logical commits. Fetch and
check status before edits; preserve unrelated work. Commit/push completed steps
on the feature branch, then open a PR after all gates pass. Link the actual
associated issue with `Closes #N`; resolve a missing association before creating
the PR. Do not commit or push main. Release publication is a separate authorized
workflow using `.claude/commands/release-dsmn.md` and public-artifact checks.

## Stop conditions and maintenance

Report a design blocker if the proposed release path requires guessing ownership
after corrupt state, treating stale closed-lid data as current, or reintroducing
agent processes as activation inputs. Resolve unlisted-file changes explicitly.
Do not hide a failing watchdog test by extending its timeout indefinitely. Review
future diagnostic additions for work inside `operationLock`; the safety path
must stay independent of their success and runtime.
