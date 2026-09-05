# Plan 001: Keep failed Repair visible and retain the release deadline

> Executor: Read this file fully, implement only its scope, and run each gate.
> Start with `git fetch --all --prune`, `git status --short --branch`, and
> `git diff --stat 513b03a..HEAD -- Sources/DSMNCore Sources/dsmnd Sources/dsmnctl Tests Package.swift docs/SAFETY.md`.
> Compare changed scoped files with the excerpts below before editing. Run from
> your checkout root; the audited checkout was `/Users/jb/.codex/worktrees/2543/dsmn`.

## Status

- Priority: P1
- Effort: M–L, including CLI failure propagation and daemon retry tests
- Risk: MED; existing successful repair behavior must remain compatible
- Depends on: none
- Category: bug
- Planned at: `513b03a`, 2026-09-05; audit finding 2
- Implementation status: DONE; reviewed on 2026-09-05

## Why this matters

Repair currently forgets ownership even if `pmset` returns a nonzero exit. The
helper then reports success and cancels its one-shot release deadline. A later
periodic reconcile may recover using live system state and old activity history,
but that is weaker than retaining responsibility for the lock. The CLI also
silently falls back to local repair for every helper error, so fixing only the
daemon would still let the CLI report false success.

## Current state and conventions

`Sources/DSMNCore/StatusReport.swift:170`:

```swift
if originalState.ownsSleepDisable || liveSleepDisabled == true {
    forcedRelease = try powerManager.setSleepDisabled(false)
}

_ = try repairState(now: now)
var report = try reconcile(powerManager: powerManager, now: now)
```

`repairState` clears `ownsSleepDisable` at line 152. By contrast, the normal
release branch in the same file records the operation and changes ownership only
when `operationSucceeded` is true: non-dry-run and exit code zero. It saves the
released state before requesting `sleepnow` for a closed lid on battery.

`Sources/dsmnd/HelperXPCService.swift:86`:

```swift
let report = try controller.repair(
    powerManager: powerManager,
    liveSleepDisabled: liveSleepDisabled()
)
scheduleSleepRelease(from: report.status)
return report
```

`Sources/dsmnctl/main.swift:68` routes Repair through `preferHelper`, whose
`try? helperOperation()` hides every error. In `Sources/DSMNCore/HelperXPC.swift`,
`decodeResponse` classifies a received helper error as `.unavailable(error)`.
There is currently no distinction between command rejection and transport loss.

Use XCTest, temporary `StateStore` directories, and injected `PowerManaging`
implementations. `Tests/DSMNCoreTests/RepairTests.swift:114` is the existing fake:

```swift
func setSleepDisabled(_ disabled: Bool) throws -> PowerOperationResult {
    requests.append(disabled)
    return PowerOperationResult(
        requestedSleepDisabled: disabled,
        dryRun: dryRun,
        executedCommand: "recorded",
        exitCode: dryRun ? nil : 0
    )
}
```

Expand this fake to queue success, nonzero, and thrown outcomes. Use the locked
fake in `Tests/dsmndTests/HelperXPCServiceSchedulerTests.swift` for timer tests.
Decode XPC JSON into `DSMNHelperCommandResponse`; source-string assertions do not
verify command behavior.

Product constraints: only the helper executes power mutations. Ownership survives
failed cleanup. An active manual lease remains valid with the lid open. Explicit
Repair ends the current lease. A successful closed-lid battery release requests
`sleepnow` afterward; AC, open-lid, unknown facts, failed release, and dry-run do
not. Local development repair does not prove that a system lock was released.

## Scope

Only modify:

- `Sources/DSMNCore/StatusReport.swift`, `PowerManager.swift`, `StateStore.swift`,
  `ReconcileSchedule.swift`, and `HelperXPC.swift`
- `Sources/dsmnd/HelperXPCService.swift`
- `Sources/dsmnctl/main.swift`
- `Tests/DSMNCoreTests/RepairTests.swift`, `DaemonReconcileTests.swift`,
  `ReconcileScheduleTests.swift`, and new `HelperCommandResponseTests.swift`
- `Tests/dsmndTests/HelperXPCServiceSchedulerTests.swift`
- New `Tests/dsmnctlTests/RepairCommandTests.swift` and its test target in
  `Package.swift`
- `dsmn.xcodeproj/project.pbxproj` only for necessary XcodeGen output
- `docs/SAFETY.md`; this plan and its index row for execution evidence

Leave the hook script, manual-command fallback behavior, UI layout, power-policy
thresholds, signing configuration, and release version unchanged. Treat
`repairState` as a local-development operation; remove its use from privileged
repair rather than changing unrelated local semantics.

## Steps and verification

### 1. Establish the failing outcomes

Add tests for owned-lock repair with nonzero, dry-run, and thrown release results.
Assert cleared timer intent, retained ownership, no `sleepnow`, and preserved
failed-attempt evidence where a `PowerOperationResult` exists. Add a successful
closed-lid battery repair test asserting `[enable_sleep, sleep_now]` ordering.

Verify: `swift test --filter RepairTests` must fail on these behavioral assertions
against the baseline, not on compilation or fixture setup. Keep the four existing
repair tests passing after implementation.

### 2. Share the existing successful-release rules

Refactor the controller's release mechanics narrowly so Repair and reconcile use
the same operation-success test, ownership update, audit persistence, and
closed-lid battery follow-up. Persist Repair's cleared manual intent before the
attempt, while retaining existing ownership. Preserve `lastStopReason = repair`
through the completed repair path.

Have the controller return the failed `DaemonRunReport` for a nonzero/dry-run
attempt; do not discard its operation result. Keep thrown launch or persistence
errors as errors. Never claim ownership of a previously unowned external lock to
manufacture retry eligibility: failure of explicit cleanup of that lock must be
reported and can be retried explicitly. The guaranteed automatic retry here is
for a lock already owned by dsmn.

Verify: `swift test --filter 'RepairTests|DaemonReconcileTests'` exits zero. Check
the saved state and operation audit, not only the returned status.

### 3. Arm retries before returning a helper failure

In the daemon Repair method, schedule from the returned state before classifying
the result. If a required release did not succeed, return an error envelope,
never `.success`. On a thrown operation, rearm from persisted owned state without
calling diagnostic probes. Add a pure state-based scheduling overload in
`ReconcileSchedule` if needed; preserve the earlier manual/no-route deadline and
the short retry when owned without a timer.

The scheduler test must call Repair once, inject a failed release followed by a
successful release, and observe recovery without another XPC call or periodic
poll. Assert an error in the initial envelope and eventual cleared ownership.
Also cover a thrown first release. Avoid a rapid unbounded retry loop.

Verify: `swift test --filter 'HelperXPCServiceSchedulerTests|ReconcileScheduleTests'`
exits zero, including the original command-then-expiry watchdog test.

### 4. Preserve helper command errors through the client and CLI

Add a distinct `DSMNHelperClientError.commandFailed(String)` for an error received
in a valid helper envelope. Decode existing error-string envelopes into this
case; this is a client-side classification and requires no XPC selector change.
Make envelope decoding internal for `@testable` tests if necessary.

For CLI Repair only, rethrow `.commandFailed` and invalid responses. Preserve
local development fallback for genuine helper transport unavailability, with
explicit stderr text that only local state was repaired. A timeout is ambiguous;
report it rather than announcing successful system cleanup. Extract an internal
closure-injected Repair routing function in `main.swift` and test it from a new
`dsmnctlTests` target, following the existing daemon executable-test pattern.

Verify: `swift test --filter 'HelperCommandResponseTests|RepairCommandTests'`
exits zero. A helper command error must not invoke the fallback closure; a
transport-unavailable fixture must invoke it exactly once. Normal manual command
compatibility is outside this change.

### 5. Document and validate

Update the Repair section of `docs/SAFETY.md` with failure, retry, dry-run, and
local-only semantics. Run every command below; attach results to the PR.

## Commands and done criteria

| Command | Required result |
| --- | --- |
| `swift test` | All tests pass; audit baseline was 145 tests |
| `xcodegen generate` | Exit zero; only justified generated changes |
| `xcodebuild -project dsmn.xcodeproj -scheme dsmn -configuration Debug -destination 'platform=macOS' -derivedDataPath DerivedData build` | BUILD SUCCEEDED |
| `./scripts/verify_bundle.sh DerivedData/Build/Products/Debug/dsmn.app` | Exit zero |
| `git diff --check` | Exit zero |
| `git diff --name-only` | Only scoped files and the generated project if regeneration genuinely changes it |

- [x] Failure-injection, closed-lid repair, XPC-envelope, CLI-routing, and
  no-further-command retry tests pass.
- [x] No failed/dry-run owned release forgets ownership or cancels its retry.
- [x] Received helper failure does not become successful CLI local repair.
- [x] Standard checks pass and the index row records evidence and status.

## Git and release workflow

When implementation is authorized, update a feature worktree from `origin/main`
and use branch `jb/repair-release-failures`. Commit and push completed logical
steps, never main. Match existing imperative commit subjects, for example
"Preserve ownership when helper repair fails". Associate a real existing GitHub
issue with the PR and include its actual `Closes #N`; do not invent an issue ID.
Resolve any missing issue association before PR creation. No issue, commit, or
release was created by this planning task.

After an authorized merge/release, follow `.claude/commands/release-dsmn.md`,
verify public artifacts and the installed helper build. A local archive alone
does not validate the shipped fix.

## Stop conditions and maintenance

Stop for a design decision if this requires weakening XPC authentication,
claiming dry-run ownership, changing timer policy, or recovering a corrupt state
file by assuming ownership. Investigate ordinary test failures; report a blocker
only when an external prerequisite or scope decision is actually missing.
Compare unexpected source drift with the excerpts and refresh this plan before
implementing a different design. Plan 002 extends diagnostic-failure handling;
it must preserve these Repair results and retries.
