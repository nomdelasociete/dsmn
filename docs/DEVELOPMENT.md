# Development modes

## Tests and ad-hoc builds

Use the four checks in [README](../README.md#build-and-test). They do not require
an Apple developer team, notarization credentials, or helper installation.
The ad-hoc flags match CI. Disabling hardened runtime there is for development
only; official release builds retain it.

A local simulation with isolated state:

```sh
state_dir="$(mktemp -d)"
DSMN_STATE_DIR="$state_dir" DSMN_APPLY_PMSET=0 swift run dsmnd daemon-once
rm -rf "$state_dir"
```

This one-shot helper uses the chosen state directory and does not change power
settings. Do not run it with sudo or set `DSMN_APPLY_PMSET=1` during ordinary
development.

`DSMN_STATE_DIR` only redirects local state. It does **not** disconnect the app
or CLI from an already registered helper: CLI commands normally try XPC first.
Use mocks/unit tests for commands if a production helper is running.

For UI work, open the ad-hoc bundle on a dedicated test account or Mac without
the production app/helper. Do not register its helper or install hooks unless
that is the explicit integration test. The existing
`script/build_and_run.sh` assumes a signing setup and stops processes named
dsmn; it is not the credential-free entry point.

## Signed helper integration and forks

The official helper only accepts expected app/CLI identifiers signed by the
official team. Ad-hoc builds are expected to fail that authentication. Merely
changing Xcode's team is insufficient.

There is currently no one-command isolated fork profile. On a dedicated test
machine, prepare and review these coordinated changes on your fork:

| Setting | Places to update |
|---|---|
| Your signing team | `project.yml`, `DSMNServiceConstants.developmentTeamID` in `HelperXPC.swift`; archive/export options if distributing |
| App, CLI, helper and framework identifiers | `project.yml`, `HelperXPC.swift`, nested codesign identifiers |
| LaunchDaemon and Mach service | Plist filename, Label, MachServices, AssociatedBundleIdentifiers, copied resource path, service constants |
| State and preferences | Root/user state paths in `StateStore.swift`, hook paths and environment prefixes, preferences domain |
| App name and hook/Raycast discovery | Build/run/packaging scripts, installer candidate paths, Raycast controller |
| Updates and feedback | Your own feed/key and HTTPS feedback endpoint, or disable those features explicitly; replace hardcoded recovery download links |

Keep the official production authentication checks intact. Sign all components
consistently with your own appropriate identity, verify their identifiers, then
register through the app's `SMAppService` flow and complete macOS approval.
Never copy a LaunchDaemon manually to bypass registration.

Test acceptance/rejection, timer expiry without another command, failed-release
recovery, lid/power transitions, helper upgrades, and unregistration. Use mocks
for critical-heat and destructive storage-failure scenarios. Clean up through
the app before deleting state or binaries.

A fork must not present itself as an official release, replace the official
helper/service, or use the official update/feedback service unintentionally.

## Official releases

Release authority stays with maintainers. Source changes and version bumps go
through feature branches and PRs; never push a release bump directly to main.
After merge, use a clean checkout of that commit for the signed release.

See [PACKAGING.md](PACKAGING.md) for tooling. A release needs its matching source
commit and corresponding source/build instructions available alongside downloads,
the project license and third-party notices, and verified public ZIP/DMG/appcast
artifacts. A local successful archive alone is not release verification.
