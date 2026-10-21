# dsmn

**Don't stop me now.** Keep your Mac awake while local AI coding agents work,
including with the lid closed.

[Download](https://dsmn.app/download/dsmn-latest.dmg) · [Website](https://dsmn.app) ·
[Contributing](CONTRIBUTING.md) · [Privacy](PRIVACY.md) · [Support](SUPPORT.md)

## Install

Download the signed, notarized app for macOS 13 or later. Open dsmn and follow
**Setup & Troubleshooting…** to register and approve its helper. Agent hooks and
launch at login are optional. Updates are delivered through Sparkle.

## What it does

- A menu bar timer, configurable presets, and Stop.
- Hooks for Claude Code, Cursor, Codex, Grok Build, and Pi that renew a bounded
  awake timer while work happens.
- A local CLI and optional [Raycast extension](raycast/README.md).
- Doctor and Why Awake diagnostics for helper, power, and agent activity.

Only the privileged helper changes system sleep settings. Timers have release
deadlines and battery, network, and thermal safeguards. Ordinary `caffeinate`
fallback does **not** provide closed-lid protection. Read the
[safety model](docs/SAFETY.md) before changing power behavior.

## Build and test

Use a Mac with Xcode providing Swift 6 or later, its command-line tools selected,
and [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.45 or later. The deployment
target is macOS 13; current Xcode may require a newer build host.

```sh
git clone https://github.com/nomdelasociete/dsmn.git
cd dsmn
swift test
xcodegen generate
xcodebuild -project dsmn.xcodeproj -scheme dsmn -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath DerivedData \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  ENABLE_HARDENED_RUNTIME=NO build
./scripts/verify_bundle.sh DerivedData/Build/Products/Debug/dsmn.app
```

This ad-hoc build needs no Apple signing credentials. It validates the app bundle;
it cannot authenticate to the official privileged helper. Do not install its
helper over a production installation. See [development modes](docs/DEVELOPMENT.md)
for dry-run commands, UI work, and signed integration testing.

Pull requests and main pushes run **macOS tests and bundle**. A successful review
does not replace passing checks. Menu changes also need a local interactive test.

## Your data

Power management runs locally. Diagnostics can contain process paths, command
arguments, project names, and session context. Review them before sharing.
Optional feedback sends a message and version information to dsmn.app; additional
diagnostics are off by default. Updates/downloads generate first-party service
measurements. [Privacy details](PRIVACY.md).

## Contributing

Bug reports, ideas, documentation, and fixes are welcome. Discuss substantial
changes in an issue first; small corrections can go straight to a PR.
[CONTRIBUTING.md](CONTRIBUTING.md) explains the workflow and checks.
Report vulnerabilities [privately](SECURITY.md).

## License

Copyright (C) 2026 Nom de la société and contributors.

dsmn's first-party code, documentation, and artwork are licensed under the
**GNU General Public License version 3 only** (`GPL-3.0-only`). See [LICENSE](LICENSE).
The separately distributed [Raycast extension](raycast/LICENSE) retains its MIT
license. Third-party components retain their own licenses; see [the inventory](docs/LICENSES.md).
Earlier copies retain any licenses already granted with them.

The license grants no right to imply that a fork is an official release.
Use distinct app/service identifiers, update endpoints, and branding for forks.

## Further reading

- [Architecture](docs/ARCHITECTURE.md) and [agent hooks](docs/HOOKS.md)
- [macOS app validation](docs/MACOS_APP.md) and [packaging](docs/PACKAGING.md)
- [Support and removal](SUPPORT.md)
- [Contributor conduct](CODE_OF_CONDUCT.md) and [agent engineering notes](AGENTS.md)
