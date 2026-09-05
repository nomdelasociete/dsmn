# dsmn implementation plans

Prepared on 2026-09-05 against `513b03a` (0.1.43, build 44), which matched freshly
fetched `origin/main`. The user selected audit findings 1–5 for implementation
plans, then authorized implementation. Execution evidence appears below.
The four implemented fixes are tracked in
[issue #92](https://github.com/nomdelasociete/dsmn/issues/92).

Read the selected plan fully before execution. Each contains its own context,
scope, regression cases, verification commands, and stop conditions. The baseline
audit ran `swift test`: 145 tests passed. Signed builds, release publication, and
live lid-close tests were not run as part of the audit or this planning pass.

## Recommended execution order

| Plan | Result | Original finding | Priority | Effort | Depends on | Status |
| --- | --- | --- | --- | --- | --- | --- |
| [001](001-preserve-failed-repair-ownership.md) | Failed Repair retains responsibility and reports failure | 2 | P1 | M–L | — | DONE |
| [002](002-release-despite-diagnostic-failures.md) | Expiry and Stop survive diagnostic failures | 5 | P1 | L | 001 | DONE |
| [003](003-edit-codex-toml-safely.md) | Codex hook installation preserves valid configuration | 3 | P1 | M–L | — | DONE |
| [004](004-retire-helper-before-unregistering.md) | Helper removal/replacement releases safely | 1 | P1 | L | 001, 002 | BLOCKED: legacy migration scope decision |
| [005](005-confirm-stop-before-quitting.md) | Stop & Quit closes only after confirmed Stop | 4 | P1 | M | 001, 002 | BLOCKED: code complete; interactive QA pending |

Effort includes regression tests and integration checks: M is roughly a day or
two; L spans several days. These estimates are deliberately larger than a local
one-line patch because each fix crosses failure or integration boundaries.

Status values: TODO, IN PROGRESS, DONE, BLOCKED (with a concrete reason), REJECTED
(with rationale). Executors update their row and append actual evidence below.
Use DONE only when every done criterion has been met. A passing unit suite alone
is not a completed signed app/helper change.

## Dependency notes

- 001 establishes common successful-release rules, ownership retention, error
  propagation, and retry scheduling.
- 002 extends that foundation so diagnostic errors and slow status collection
  cannot prevent cleanup. It must retain 001's failure behavior.
- 004 uses both release guarantees for helper retirement. Its first step is a
  compatibility gate: the shipped helper has no atomic retirement operation.
  Resolve a safe legacy migration or an explicit staged rollout before wiring
  the new lifecycle path. A Stop-then-unregister race is not a completed fix.
- 005 benefits from 004's app test target and should normally follow it to avoid
  conflicting edits in the store and helper client. It can proceed after 001/002
  if the legacy rollout decision holds up 004; its plan includes test-target setup.
  Its app-only interface can be implemented in parallel with 002 after 001, but
  final validation must include the completed helper changes.
- 003 is independent and can run in its own worktree. Coordinate `Package.swift`
  and generated project changes with the app/CLI test target additions.

All documents stamp the audited baseline. When a prerequisite changes an excerpt,
verify the prerequisite's stated contract against live code and update the
dependent plan's execution notes; do not revert the prerequisite to restore an
old excerpt. Unexpected semantic drift requires refreshing the affected plan.

## Verification and execution boundaries

Every implementation must run the four checks required by `AGENTS.md`:

```sh
swift test
xcodegen generate
xcodebuild -project dsmn.xcodeproj -scheme dsmn -configuration Debug -destination 'platform=macOS' -derivedDataPath DerivedData build
./scripts/verify_bundle.sh DerivedData/Build/Products/Debug/dsmn.app
```

Plans 004/005 also require the menu E2E script and targeted interaction evidence.
Dependency/packaging changes require archive verification. Publishing and
validating a release follows `.claude/commands/release-dsmn.md` after an authorized
merge; check public downloaded artifacts and the locally installed helper build.

Update a feature worktree from main before coding. Follow the `jb/` branch names
in the plans, commit/push completed logical implementation steps, and open a PR
after required checks pass. Use a real issue association in its `Closes #N` body;
no issue IDs were assigned during planning. Never commit or push directly to main.
Implementation is being integrated on `jb/reliability-improvements`.

## Explicitly deferred findings

These remain useful work, but were not selected for this set of five plans:

- Audit finding 6: emit fallback-resolved hook events only after confirming
  protection, rather than accepting an active timer as proof.
- Audit finding 7: a complete root verification entrypoint and macOS PR CI.
  These plans add behavior tests where needed; they do not implement the whole
  CI or menu-store architecture project.
- Audit finding 8: assert signed identifiers before upload, then verify the actual
  public appcast, ZIP, and DMG rather than HTTP headers alone.
- Reconcile observed lock-off state when persisted ownership still says on.
- Cover enabling with an already-recorded closed lid in display-sleep tests.
- Parse hook payloads only after the throttle check; cap logs and bound inspection.
- Reconcile stale/conflicting release documentation, including generated plist
  staging examples and direct-main release instructions.
- Product options: a recent power-operation timeline and selected agent integrations.

## Findings considered and rejected

- Releasing an active timer just because the lid opens: contrary to the explicit
  product model; open-lid grace is informational.
- Removing pre/post tool events to reduce load: throttle manual renewal calls
  instead; event coverage is intentional.
- Treating ordinary helper build drift as broken setup: it is advisory while the
  helper responds, with an explicit Update Helper and Later path.
- Replacing the privileged helper with caffeinate: it loses closed-lid protection.
- A broad rewrite of the menu store before behavior tests: defer extraction until
  failure and lifecycle transitions have executable coverage.
- A speculative Sparkle migration or product-security finding from Raycast audit
  noise: the audit found matching Sparkle resolutions and did not establish a
  reachable product vulnerability from the reported build-tool advisory.

## Execution evidence

### 001 — reviewed and integrated

Executor commits `92fe16a`, `4613a8c`, and `8fdfe86` on
`jb/repair-release-failures`; integrated as `898a7e2`, `ffac285`, and `b0608e1`.
Reviewer read the complete diff and behavior assertions, then independently ran
all four gates: 169 Swift tests passed, XcodeGen succeeded, Xcode Debug build
succeeded, and bundle verification succeeded. The executor also passed these
gates. No installed app, hooks, helper registration, or real power state changed.
The scheduler now retries an owned lock without a lease after one second even
if an old no-route timestamp remains; this is necessary to avoid delaying Repair.

### 002 — reviewed and integrated

Added `AgentDetector.swift` and process-list tests to scope: `PSProcessListing`
has a separate unbounded `Process` implementation, so changing only
`ProcessCommandRunner` would leave the diagnostic hang intact.

Executor commits `071ccbd`, `77110f3`, `d037e13`, `77be3b2`, and `c0f0a24`
on `jb/release-despite-probe-failures`; integrated as `0adfafa`, `e54a255`,
`d6d83e7`, `136db04`, and `e360efb`. Reviewer read the complete implementation
and regression diffs. Independent review also checked helper scheduling races.
The final combined suite passed 233 tests; XcodeGen, signed Debug build, and
bundle verification passed independently on the integration branch.

Optional telemetry now runs outside the helper's power-operation lock, and
subprocess execution has a bounded timeout with child termination/reaping.
State-based deadlines retain failed-release ownership and retry without a new
command. Regression tests gate telemetry while Stop and expiry release the lock,
reject obsolete telemetry and sleep follow-ups after a new command, and require
a fresh live probe for unowned Repair. Successful acquisition is persisted
before a potentially failing display-sleep operation. Cached closed-lid data
cannot sleep the display: fresh accepted observations drive that follow-up once.

The Stop/Repair client budgets cover bounded cleanup operations; heavy contention
can still produce an ambiguous timeout. Tests use injected power managers and
temporary state. No installed helper or real power setting was changed.

### 004 — compatibility gate

The shipped protocol has no admission barrier. Native asynchronous unregister
waits for helper termination but cannot first stop legacy lease admission.
A Stop/check/unregister sequence remains racy. A separate, durably armed,
signed migration guard is a possible automatic migration design, but expands
packaging/state scope and still needs signed integration proof. The user has
been asked whether to include that expansion or finish the other four fixes.
No lifecycle code has been changed.

### 003 — reviewed and integrated

Executor commits `b240d3e` and `c901b11` on `jb/safe-codex-feature-editing`;
integrated as `21a991e` and `7006c48`. Reviewer read the complete source,
manifest, generated project, documentation, and test diffs. The combined suite
with 001 passed 183 tests; XcodeGen, Debug build, and bundle verification passed.
Both executor and reviewer also ran a signed universal archive/export and
verified the exported bundle. The reviewer confirmed x86_64/arm64 framework
slices, system-only runtime library dependencies, exact CLI/helper signing
identifiers, and byte-identical bundled third-party notices. Sparkle stayed at
2.9.2 with its original revision in both lockfiles.

Approved scope addition: `Sources/dsmnapp/Resources/THIRD_PARTY_NOTICES.txt`,
containing the native parser licenses. Embedded NUL bytes are rejected because
TOMLKit's C-string parser would otherwise accept only the prefix. Test fixtures
use temporary homes. Archive preparation read only the installed app's public
Sparkle key; it did not alter the installed app or actual Codex configuration.
Release publication remains separate from this implementation.

### 005 — implementation and integration reviewed; interactive QA pending

Executor commits `f0fd67e`, `26c7497`, and `1dad99e` on
`jb/confirm-stop-before-quit`; integrated as `7c06e7b`, `f78032d`, and `09c2860`.
Reviewer read all source/test/documentation and generated project changes.
The combined suite with 001/003 passed 201 tests, including 18 app behavior tests;
XcodeGen, signed Debug build, and bundle verification also passed independently.
Final integration with 002 subsequently passed all 233 tests and the same four
standard gates. The implementation is complete; targeted interactive checks
remain outstanding, so its PR must stay a draft.

A disposable app hosted the real menu view with a simulated active report and
an injected failing Stop operation. The user objected to the visible test window;
it was immediately closed, and all further checks remain in the background.
No buttons had been clicked and no injected helper call had occurred. The real
alert interaction is therefore unverified, and `e2e_menu_setup.sh` has not run.
Only that harness's preferences and temporary state were cleaned up; the
installed app, helper registration, and actual power settings were not changed.
Evidence is retained in `/tmp/dsmn-quit-qa-Dgx2E8/QA_RESULT.md`.

### Final combined background verification — 2026-09-05

All implementation commits through `e360efb` were verified together:

- `swift test`: 233 tests, zero failures (baseline: 145).
- `xcodegen generate`: exit zero, no unexplained generated changes.
- Required signed Debug `xcodebuild`: BUILD SUCCEEDED.
- `verify_bundle.sh` on the Debug app: exit zero.
- `archive.sh`: ARCHIVE SUCCEEDED and EXPORT SUCCEEDED.
- `DSMN_REQUIRE_SPARKLE=1 verify_bundle.sh dist/export/dsmn.app`: exit zero.
- Exported DSMNCore contains arm64/x86_64 slices and only system runtime
  dependencies; bundled parser notices match their source byte for byte.
- Exported signing identifiers match the required app, CLI, and helper values.
- `git diff --check`: exit zero. Fetched `origin/main` remains `513b03a`.

Local logs are `/tmp/dsmn-final-tests.log`, `/tmp/dsmn-final-build.log`,
`/tmp/dsmn-final-bundle.log`, `/tmp/dsmn-final-archive.log`, and
`/tmp/dsmn-final-export-check.log`. No notarization, release publication, local
installation, helper registration change, or live lid/power test was performed.
Interactive menu verification remains outstanding; open only a draft PR.
