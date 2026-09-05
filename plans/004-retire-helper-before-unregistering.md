# Plan 004: Retire the helper safely before unregistering or replacing it

> Executor: Begin with `git fetch --all --prune`, `git status --short --branch`,
> and `git diff --stat 513b03a..HEAD -- Sources/DSMNCore Sources/dsmnd Sources/dsmnapp Tests Package.swift docs`.
> Plans 001 and 002 deliberately change the release machinery. Verify their
> contracts below against the completed code, and adapt excerpts only for those
> documented prerequisites. Resolve unexpected drift before implementation.

## Status

- Priority: P1
- Effort: L; includes an explicit legacy-helper compatibility gate
- Risk: HIGH; lifecycle and cross-version XPC behavior
- Depends on: `001-preserve-failed-repair-ownership.md` and
  `002-release-despite-diagnostic-failures.md`
- Category: bug
- Planned at: `513b03a`, 2026-09-05; audit finding 1
- Implementation status: TODO

## Why this matters

The app unregisters the daemon without first releasing its sleep lock. macOS
terminates a running LaunchDaemon on unregister. The global power setting can
therefore outlive the daemon, with no timer left to expire it. A helper update
has the same failure if unregister succeeds but the new registration fails or
needs approval. [Apple's unregister documentation](https://developer.apple.com/documentation/ServiceManagement/SMAppService/unregister%28%29)
confirms the service termination behavior.

A correct solution also handles another hook arriving during removal. A separate
Stop call followed by unregister is not an atomic retirement operation. Older
shipped helpers have no retirement selector, so the first rollout needs an
explicit compatibility decision backed by tests; do not disguise that gap as a
transport fallback.

## Current state and conventions

`Sources/dsmnapp/Services/HelperServiceClient.swift:43`:

```swift
func unregister() throws -> HelperRegistrationStatus {
    try SMAppService.daemon(plistName: DSMNServiceConstants.helperPlistName).unregister()
    return registrationStatus
}

func updateRegistration() throws -> HelperRegistrationStatus {
    let service = SMAppService.daemon(plistName: DSMNServiceConstants.helperPlistName)
    try service.unregister()
    try service.register()
    return registrationStatus
}
```

`DSMNMenuStore.updateHelper()` and `unregisterHelper()` call these synchronous
methods before refreshing status. `Sources/dsmnd/DSMND.swift:39` creates the
service, starts reconciliation, resumes the XPC listener, and runs the main
run loop. There is no signal-driven cleanup. Service deinitialization only
cancels timers.

The XPC protocol in `Sources/DSMNCore/HelperXPC.swift` exposes status, manual,
Stop, reconcile, and Repair. Both old and new signed app/CLI clients can connect.
`DSMNHelperXPCService` serializes mutation with `operationLock`; use this boundary
for retirement so an in-flight hook cannot slip between release and admission
control. Do not rely on the app's main actor to serialize other clients.

Match the existing patterns: `@MainActor` app services, async XPC wrappers,
typed values in DSMNCore, XCTest with dependency injection, and daemon fakes
protected by locks. The existing executable test target `dsmndTests` in
`Package.swift` is the model for a new `dsmnappTests` target.

Required prerequisite behavior: Plan 001 preserves ownership on failed release,
records outcomes, distinguishes command failure from unavailable transport, and
rearms cleanup. Plan 002 makes release independent of optional diagnostics and
bounds subprocess execution. Reuse those contracts, not another direct `pmset`
implementation.

Product constraints: ordinary helper build drift remains advisory with Update
Helper and Later. Only explicit lifecycle actions change registration. Keep
bounded manual intent across a successful app/helper update without extending
its absolute expiration. Full helper removal ends intent. Only the privileged
helper changes power settings, and `SMAppService` owns registration.

## Scope

Only modify:

- `Sources/DSMNCore/HelperXPC.swift`, `StatusReport.swift`, `StateStore.swift`
- `Sources/dsmnd/HelperXPCService.swift`, `DSMND.swift`
- `Sources/dsmnapp/Services/HelperServiceClient.swift`
- New `Sources/dsmnapp/Services/HelperLifecycleCoordinator.swift`
- `Sources/dsmnapp/Stores/DSMNMenuStore.swift`
- `Sources/dsmnapp/Views/DSMNSetupTroubleshootingView.swift` for lifecycle status
  and actionable failure copy only
- New `Tests/dsmndTests/HelperRetirementTests.swift`
- New `Tests/DSMNCoreTests/HelperRetirementCoreTests.swift`
- New `Tests/dsmnappTests/HelperLifecycleCoordinatorTests.swift`; `Package.swift`
  for the new app test target
- `Tests/DSMNCoreTests/HelperCommandResponseTests.swift` from Plan 001
- `docs/ARCHITECTURE.md`, `docs/SAFETY.md`, `docs/MACOS_APP.md`
- This plan/index and necessary generated `dsmn.xcodeproj/project.pbxproj` changes

No weakened signature checks, hand-copied LaunchDaemons, root power commands in
the app, automatic unregister/register on wake, broad menu redesign, or changes
to the ordinary helper-update advisory policy. Test fixtures must not operate on
the installed helper or real Login Items.

## Steps and verification

### 1. Resolve cross-version behavior before wiring the UI

Write a compatibility matrix for new app/new helper, new app/legacy helper,
legacy app/new helper, unavailable helper, registration requiring approval, and
new registration failure. Add protocol/coordinator fixtures that model each case.
Record the chosen rollout in this plan's execution notes before proceeding.

The target protocol is an explicit prepare-for-unregister operation with a
preserve-lease flag and a client-generated opaque token, plus a token-matched
cancellation/resume operation. A returned retirement
acknowledgment must mean the helper has stopped admitting leases and its owned
lock has been released. Retain existing selectors for old signed clients.

An old helper cannot acquire that admission barrier. Prove a safe legacy migration
strategy in an isolated signed test setup. If the only available strategy is a
racy Stop-then-unregister sequence, report that limitation and obtain a rollout
decision before enabling the new caller path. A staged capability rollout may be
necessary. Do not ship an Update Helper action that always fails for every older
helper, and do not mark the plan complete with this compatibility question open.

Verify: `swift test --filter HelperLifecycleCoordinatorTests` executes the matrix
fixtures. Unsupported capability and ordinary transport failure must be separate
outcomes, with neither automatically invoking unregister. This first gate may
identify a genuine design blocker; record its concrete evidence if so.

### 2. Implement serialized retirement in the helper

Under the same lock as manual mutations, transition the service from running to
retiring before releasing power. Reject new manual requests from every selector
while retiring; an already-running request finishes before preparation begins.
Repeated preparation is idempotent. Status remains readable. Periodic and
deadline callbacks must not reacquire a released lock while retirement is active.

Use the shared release mechanics. For replacement, preserve the original absolute
`manualUntil`; for removal, clear it. Record the release and retain responsibility
and bounded retries if the attempt fails. Only return the acknowledgment after a
successful owned release and a bounded confirming live-state check when a lock
was owned. Unknown confirmation is an error, not permission to unregister.
Do not appropriate an unrelated external lock merely because global
`SleepDisabled` is on when dsmn has no ownership or applicable cleanup history.

If unregister fails and the same helper is still reachable, the explicit cancel
operation leaves retirement and reconciles the remaining original lease under
normal safety policy. Use the opaque retirement token to reject a stale cancel
from an earlier operation. Cancellation must also invalidate a not-yet-started
prepare with that token, so a late request after a client timeout cannot strand
the helper in retirement. Preserve a Stop received during retirement: cancellation
must not resurrect its cleared lease. Keep retirement admission state local to the helper
instance; a replacement daemon starts normal reconciliation of persisted bounded
intent. Do not reset the timer to a fresh full duration.

Verify: `swift test --filter 'HelperRetirementTests|HelperRetirementCoreTests'`
exits zero. Tests must cover hook requests concurrent with prepare, repeated
prepare, failed/nonzero/dry-run release, unknown confirmation, stale cancellation,
expiry during retirement, and restart with the original remaining lease.

### 3. Coordinate app registration through injectable boundaries

Add a small main-actor coordinator with injected helper lifecycle operations and
registration operations. The ordered replacement sequence is prepare/acknowledge,
unregister, register, refresh. The removal sequence omits register. The
coordinator returns a typed outcome distinguishing failure before unregister,
failure after unregister, and approval required.

On preparation failure or timeout, leave registration intact, attempt cancellation
with the already-known request token, and show the concrete error. A failed
cancellation is also visible and can be retried; do not leave a silent admission
barrier after reporting that the app has returned to normal operation.
On unregister failure, attempt token-matched cancellation on the original helper;
report both failures if cancellation also fails. On replacement failure after
successful unregister, keep the released state truthful and offer registration
retry; do not start a local timer or silently renew the lease. Use the approved
legacy behavior from step 1 explicitly. Prevent duplicate app lifecycle actions
while one is in flight without disabling the user's Stop action.

Make `HelperServiceClient.unregister` and `updateRegistration` async as needed,
and update only their existing store call sites. Preserve the explicit Update
Helper/Later experience and transient XPC retry behavior.

Verify: `swift test --filter HelperLifecycleCoordinatorTests` exits zero. Assert
the exact recorded action order and zero unregister calls on failed preparation;
assert that failed registration cannot leave an owned lock behind. Tests call
fake registration operations only.

### 4. Add bounded termination cleanup as a fallback

Handle normal SIGTERM/SIGINT through a Dispatch signal source or equivalent safe
mechanism in `DSMND`, not Foundation work inside an async signal handler. Stop
admitting leases, perform bounded owned-lock release through the shared service
path, persist the result, and exit. Repeated retirement/termination is idempotent.
Do not rely on `deinit`, and do not claim cleanup survives SIGKILL or power loss.
Keep persisted ownership available to normal restart recovery on failure.

Test the cleanup coordinator directly with fakes. If a process-level signal test
is added, launch an isolated dry-run helper with a temporary state directory;
never signal the installed system job.

Verify: `swift test --filter 'HelperRetirementTests|HelperXPCServiceSchedulerTests'`
exits zero, including existing release watchdog tests and no duplicate power
release after an already successful retirement.

### 5. Validate UI, packaging, and rollout

Update architecture/safety/app docs with retirement semantics and the resolved
compatibility matrix. Run the standard gates and the menu interaction script.
In the controlled signed setup, verify the new/legacy matrix, active replacement,
failed registration, and explicit removal. Record app/helper build identifiers
and actual lock state before and after; retain normal open-lid timer behavior.

## Commands and done criteria

| Command | Required result |
| --- | --- |
| `swift test` | All tests pass, including prior plans |
| `xcodegen generate` | Exit zero |
| `xcodebuild -project dsmn.xcodeproj -scheme dsmn -configuration Debug -destination 'platform=macOS' -derivedDataPath DerivedData build` | BUILD SUCCEEDED |
| `./scripts/verify_bundle.sh DerivedData/Build/Products/Debug/dsmn.app` | Exit zero |
| `./scripts/e2e_menu_setup.sh` | Exit zero; explicit setup controls remain operable |
| `git diff --check` | Exit zero |
| `git diff --name-only` | Only scoped files |

- [ ] Compatibility matrix is resolved and evidenced, including legacy migration.
- [ ] Admission-barrier, release-failure, cancellation, and restart tests pass.
- [ ] Failed preparation cannot call unregister; failed replacement leaves no
  dsmn-owned lock with no running cleanup mechanism.
- [ ] Replacement preserves the absolute expiry; removal clears intent.
- [ ] New app tests execute behavior rather than source-string checks.
- [ ] Signed integration evidence and index status are recorded.

## Git and release workflow

Use `jb/safe-helper-retirement`, based on main containing Plans 001 and 002.
Fetch/check status before edits; commit and push completed logical steps on that
feature branch. Run all gates before creating the PR, with its real issue's
`Closes #N` link. Resolve the issue association before PR creation. Never push
main or invent an issue number.

This change affects XPC compatibility. When distribution is authorized, run
`./scripts/archive.sh`, `./scripts/verify_bundle.sh dist/export/dsmn.app`, and the
repository's notarization flow. After merge use `.claude/commands/release-dsmn.md`
and verify downloaded public ZIP/DMG contents and exact app/CLI/helper signing
identifiers. Check the installed app and helper parent bundle build separately;
publishing does not update the maintainer's running helper automatically.

## Stop conditions and maintenance

The unresolved legacy compatibility gate is a real stopping condition, not an
invitation to add an unsafe fallback. Also stop for a design decision if a fix
requires force-killing the root helper from the app, extending a preserved lease,
or automatic registration recovery. Future XPC methods that can acquire a lock
must obey the retirement admission barrier. Review shutdown retries and timer
callbacks together so no callback can reacquire during retirement.
