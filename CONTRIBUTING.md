# Contributing to dsmn

Bug reports, ideas, documentation, and code are welcome. dsmn has a privileged
helper: correctness and understandable behavior matter more than adding options.

## Start with the problem

Open an issue before a substantial change. Explain what happens, what you expect,
and why the change helps. Typos and obvious small fixes can go directly to a PR.
For vulnerabilities, use [SECURITY.md](SECURITY.md), not a public issue.

Include app/build and macOS versions in bug reports. Use invented project names
and synthetic examples. Do not paste raw status JSON, hook logs, agent configs,
tokens, or private paths. [SUPPORT.md](SUPPORT.md) explains safe diagnostics.

## Make the change

1. Fork and branch from current `main`. Keep one coherent change per PR.
2. Follow [development modes](docs/DEVELOPMENT.md). Core tests and an ad-hoc
   bundle need no maintainer credentials. Signed helper tests are separate.
3. Read the relevant [architecture](docs/ARCHITECTURE.md), [safety rules](docs/SAFETY.md),
   and [AGENTS.md](AGENTS.md). Match surrounding Swift 6 and TypeScript style.
4. Put shared logic in `DSMNCore`; keep app views focused on presentation.
   Add focused regression tests for behavior changes, especially failure paths.
5. Keep documentation true in the same change. Power decisions and hook changes
   also update `docs/SAFETY.md` and `docs/HOOKS.md`.
6. Open a PR describing the problem, resulting behavior, linked issue, and actual
   checks run. Say explicitly when a hardware or interactive check was not run.

## Checks

Run all four commands from the [README build section](README.md#build-and-test):
`swift test`, `xcodegen generate`, the ad-hoc Debug `xcodebuild`, and
`scripts/verify_bundle.sh`. Keep dependency lockfiles committed; explain updates.

For menu interactions, run `./scripts/e2e_menu_setup.sh` on a dedicated unlocked
test account/Mac with Accessibility permission, then inspect the live menu.
The script builds and opens the app and can affect a running dsmn instance; do
not run it while someone relies on that instance. Report the tested OS and build.

For Raycast changes, run `npm ci --prefix raycast`,
`npm run build --prefix raycast`, and `npm run lint --prefix raycast`.
For distribution changes, maintainers also validate the signed archive,
notarization, update metadata, and public artifacts using the packaging runbook.
Contributors do not need or receive official signing/publishing keys.

## Rules worth keeping close

- Only the helper changes system sleep settings. A UI or hook sends intent.
- Preserve release deadlines, failed-release ownership, and critical-heat safety.
- Stop stays accessible during setup problems. Helper version drift alone is advisory.
- Hook installation/uninstallation preserves unrelated user configuration.
- Test data is invented. Never commit real diagnostics, credentials, or private
  infrastructure details, including in screenshots, PR text, or review comments.
- New network behavior must be documented in `PRIVACY.md` and explained to users.
- Do not weaken production XPC authentication to make a development build work.

## Review and license

Maintainers decide scope, review changes, and publish official releases. Expect
discussion for changes to helper trust, safety policy, data collection, or release
automation. Passing CI is necessary, but it does not imply a PR will be accepted.

By submitting a contribution, you agree to license it under
**GPL-3.0-only**, the same license as dsmn, and confirm you have the right to do so.
Contributions to the separately distributed `raycast/` extension are under
its existing [MIT license](raycast/LICENSE) instead.
Contributors retain their copyright; no copyright assignment is requested.
Identify third-party material and preserve its license and attribution.
AI-assisted changes meet the same ownership, privacy, testing, and review rules.

Everyone participating follows the [code of conduct](CODE_OF_CONDUCT.md).
