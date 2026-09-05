# Plan 003: Enable Codex hooks without corrupting its configuration

> Executor: Start with `git fetch --all --prune`, `git status --short --branch`,
> and `git diff --stat 513b03a..HEAD -- Sources/DSMNCore/AgentHookInstaller.swift Tests/DSMNCoreTests/AgentHookInstallerTests.swift Package.swift project.yml docs/HOOKS.md`.
> Compare the current code with the excerpts below. This plan is independent of
> the power-management plans. Run commands from your feature checkout root.

## Status

- Priority: P1
- Effort: M–L; includes parser integration in both build systems
- Risk: MED; this code edits another application's user configuration
- Depends on: none
- Category: bug
- Planned at: `513b03a`, 2026-09-05; audit finding 3
- Implementation status: DONE; reviewed on 2026-09-05

## Why this matters

Installing dsmn's Codex integration can turn valid TOML into invalid TOML. The
installer then reports current hooks without validating the feature flag. The
audit reproduced this with the actual installer and a disposable temporary home:
`[features] # valid table comment` followed by `hooks = false` acquired a second
`[features]` table. The user's real Codex files were not modified.

The target is a validated, minimal edit. Preserve unrelated values, comments,
ordering, and newline style. Refuse an edit that cannot be proven safe rather
than rewriting the whole configuration or silently dropping its contents.

## Current state and conventions

`Sources/DSMNCore/AgentHookInstaller.swift:1089` recognizes only a whole-line header:

```swift
let trimmed = line.trimmingCharacters(in: .whitespaces)
guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else {
    continue
}
```

If no literal features header is found, `enableTomlFeature` appends another table.
At line 1030 it also uses `(try? String(contentsOf: path, encoding: .utf8)) ?? ""`,
which treats read failures as an empty file. `installCodexHook` writes
`hooks.json` before preparing the TOML change. `inspectTarget` groups Codex with
Claude/Grok and checks only JSON hook commands.

`Tests/DSMNCoreTests/AgentHookInstallerTests.swift` already constructs a temporary
home, instantiates `AgentHookInstaller(homeDirectory: home, dsmnctlPath: ...)`,
and reads the resulting JSON and TOML. Follow that pattern; never test against
the real `~/.codex` directory. Existing installation tests check a simple
`[desktop]` configuration, but do not parse the resulting TOML.

The repository has SwiftPM and XcodeGen manifests. A native parsing dependency
must be declared for DSMNCore in both. The macOS deployment target remains 13.
Uninstall must preserve `features.hooks`; mixed JSON hook groups must retain
unrelated commands and matchers. All existing agent events remain installed.

## Scope

Only modify:

- `Sources/DSMNCore/AgentHookInstaller.swift`
- New `Sources/DSMNCore/CodexFeatureConfiguration.swift`
- `Tests/DSMNCoreTests/AgentHookInstallerTests.swift`
- New `Tests/DSMNCoreTests/CodexFeatureConfigurationTests.swift`
- `Package.swift`, `Package.resolved`, `project.yml`
- Generated `dsmn.xcodeproj/project.pbxproj` and
  `dsmn.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- `docs/HOOKS.md`; this plan and its index row

No new Python requirement, bundled interpreter, general configuration editor,
changes to the hook script, non-Codex installer changes, release version bump,
or automatic repair of an already-invalid user configuration.

## Steps and verification

### 1. Establish parser compatibility and the failing fixture

Use a real TOML parser to validate both the original and proposed documents.
Start with the native Swift TOMLKit package at
`https://github.com/LebJe/TOMLKit.git`, tag `0.5.0` (verified tag commit
`be015e1a4f84b5aeae3ce4c4eab5ff6ca7ce7ff9`). Pin the selected version in both
manifests and lockfiles for this change. Its documented parsing entry point is
`TOMLTable(string:)`; keep the dependency behind the new core configuration type.

This is a compatibility gate, not a claim that the dependency was built during
planning. Verify Swift 6, macOS 13, and Xcode framework/helper linking before
building the editor around it. Inspect the resolved package license and runtime
dependencies. Do not upgrade Sparkle while resolving this package.

Add the commented-header regression and assert that parsing succeeds after
installation, exactly one semantic `features` table exists, `hooks` is true,
and unrelated values match. The parser must reject the baseline duplicate output.

Verify: `swift test --filter CodexFeatureConfigurationTests` builds and its
parser smoke tests pass; the installer regression fails on the duplicate-table
assertion. Then run `xcodegen generate` and the Xcode build command below to
prove the native dependency links in both build paths before proceeding.

### 2. Implement a validated surgical edit

Give `CodexFeatureConfiguration` a small pure API that reads feature readiness
and produces either unchanged text, safely edited text, or a descriptive error.
Parse the whole original first. Produce a minimal text patch, parse the candidate,
and compare its semantic tree with the original: only `features.hooks` may change
to true. Use parser data for semantic identity; a narrow scanner may locate the
text range but must understand quoted strings, comments, and multiline strings
so header-like text inside values cannot be mistaken for a table.

Support absent configuration, no features table, ordinary or quoted features
headers with trailing comments, missing hooks keys, and existing true/false
boolean keys with comments. Preserve LF/CRLF and comments around the edited
value. An already-true semantic feature flag is unchanged even if its spelling
uses dotted keys or an inline table.

For a valid representation that the bounded editor cannot safely modify (for
example a false flag inside an inline table), return an explicit unsupported-edit
error before writing. Do not append a duplicate table or serialize the whole
file as a shortcut. Document this bounded support; support for every TOML editing
form is not a prerequisite for fixing configuration corruption.

Verify: `swift test --filter CodexFeatureConfigurationTests` exits zero. Every
successful candidate parses, has the intended flag, preserves unrelated values,
and changes only the permitted byte range(s). Unsupported and invalid input
returns an error with byte-identical original text.

### 3. Integrate safe writes and truthful inspection

Distinguish a missing file from unreadable or invalid UTF-8 input. Prepare and
validate the Codex TOML candidate before modifying existing Codex configuration
files. Keep atomic replacement, preserve applicable file permissions, and detect
a changed original immediately before replacement so an observed concurrent
edit is not overwritten. Do not claim this is a cross-process transaction that
Codex itself participates in.

Validate existing hooks JSON before writing TOML as well. A preparation/validation
failure must leave both existing Codex files byte-identical. If an I/O failure
occurs between the two replacements, report the partial result accurately and
make a rerun idempotent; do not promise atomicity across two files or roll back
over an intervening user edit.

Give Codex its own inspection branch: current means the shared script and JSON
events are current AND valid TOML has semantic `features.hooks == true`.
Missing/false/invalid configuration must not be reported current. Use existing
missing/outdated/error reporting conventions rather than adding a new UI flow.

Verify: `swift test --filter AgentHookInstallerTests` exits zero. Test successful
installation, exact-byte idempotence on the second run, invalid/unreadable input,
and inspection with valid JSON but missing/false/invalid TOML. Test a deliberately
injected changed-original check instead of timing a real concurrent editor.

### 4. Preserve integration behavior and document the limitation

Keep every installed event and the shared shell script unchanged. Uninstall
must still remove individual dsmn JSON hooks while preserving unrelated entries,
and must not revert the Codex feature flag. Explain unsupported safe-edit cases
in `docs/HOOKS.md`, including the path and a clear error rather than configuration
contents. Never log entire user configuration or secrets.

Verify: `swift test --filter AgentHookInstallerTests` exits zero with all existing
target, mixed-group, inspection, and uninstall tests still running. Run the full
gates below and review lockfile changes for unrelated dependencies.

## Test matrix

| Input | Required outcome |
| --- | --- |
| No config / empty valid config | One valid features table with hooks enabled |
| `[features] # comment` and false hooks | Change the flag; preserve header/comment |
| Following table has a trailing comment | Insert/update only inside features |
| Header-like text in multiline strings | Preserve it as value content |
| Quoted features/header/key with true hooks | Parse as true; no duplicate definition |
| Valid unsupported inline/dotted false form | Explicit error; original bytes preserved |
| Duplicate table / malformed TOML / invalid UTF-8 | Error; no destructive rewrite |
| Read failure / detected intervening edit | Error; no replacement |
| Current JSON with false/missing feature flag | Inspection not current |
| Install twice, then uninstall twice | Idempotent; feature flag retained |

## Commands and done criteria

| Command | Required result |
| --- | --- |
| `swift test` | All tests pass |
| `xcodegen generate` | Exit zero |
| `xcodebuild -project dsmn.xcodeproj -scheme dsmn -configuration Debug -destination 'platform=macOS' -derivedDataPath DerivedData build` | BUILD SUCCEEDED |
| `./scripts/verify_bundle.sh DerivedData/Build/Products/Debug/dsmn.app` | Exit zero; nested executables load DSMNCore successfully |
| `git diff --check` | Exit zero |
| `git diff --name-only` | Only scoped files |

- [ ] Commented-header regression is fixed with parser-based assertions.
- [ ] All matrix cases pass without touching a real user home.
- [ ] SwiftPM and Xcode dependency resolutions agree; Sparkle is unchanged.
- [ ] Invalid/unreadable/unsupported input cannot become an empty replacement.
- [ ] Inspection verifies the feature flag; uninstall still preserves it.
- [ ] Index row records implementation and verification evidence.

## Git, release, and references

Use feature branch `jb/safe-codex-feature-editing`, based on freshly fetched main.
Commit/push logical completed steps and open a PR after all four standard gates;
link the real associated issue with `Closes #N`. Resolve the issue association
before PR creation, and never commit or push main. Match imperative subjects such
as "Validate Codex configuration before enabling hooks".

Because a dependency enters the shipped framework, also validate the archive
with `./scripts/archive.sh` and
`./scripts/verify_bundle.sh dist/export/dsmn.app`. Follow the repository's
notarization and public-artifact release flow when publication is authorized.
After updating the installed app, use its embedded CLI to reinstall hooks as
specified in `AGENTS.md`.

Primary references: [TOML tables and comments](https://toml.io/en/v1.0.0#table),
[TOMLKit API](https://github.com/LebJe/TOMLKit), and
[package manifest](https://github.com/LebJe/TOMLKit/blob/main/Package.swift).
The documented parser supports native Swift parsing; it is not being assumed
to preserve comments when serializing. Use validation plus a text patch.

## Stop conditions and maintenance

Report a dependency decision if the compatibility gate fails, licensing is
unsuitable, or the package requires deployment/runtime changes outside scope.
Do not silently replace it with Python or vendor an unreviewed parser. Refuse a
configuration edit whose semantic comparison changes anything beyond the feature
flag. Future support for additional TOML forms should add fixtures to this matrix
before broadening the editor.
