# License and attribution inventory

## Project

Copyright (C) 2026 Nom de la société and contributors.

First-party dsmn code, documentation, and artwork are **GPL-3.0-only**, except
the separately distributed `raycast/` extension, which retains its MIT license.
[LICENSE](../LICENSE) contains the unmodified GNU GPL version 3 text; its example
“or later” notice is instructional text, not this project's license election.
The README and this declaration select version 3 only.

Contributions follow [CONTRIBUTING.md](../CONTRIBUTING.md). Contributors retain
copyright. Earlier distributed copies retain any licenses already granted,
including the Raycast extension's MIT declaration.

The app bundles the full license as `dsmn-LICENSE.txt`, plus
`dsmn-COPYRIGHT.txt` identifying the project and exact license choice.
The repository's license is not a grant of trademark rights or endorsement.
Forks must clearly identify their publisher.

## Third-party material

These components retain their upstream licenses; they are not relicensed as
first-party dsmn code. Versions below match the committed Swift lockfiles.

| Component | Version / origin | License and bundled notice |
|---|---|---|
| Sparkle | 2.9.2, sparkle-project/Sparkle | MIT plus its external-component notices, `Sparkle-LICENSE.txt` |
| TOMLKit | 0.5.0, LebJe/TOMLKit | MIT, `THIRD_PARTY_NOTICES.txt` |
| toml++ and UTF-8 decoder | Included by TOMLKit | Upstream MIT notices, `THIRD_PARTY_NOTICES.txt` |
| Geist Pixel Square | Vercel / basement.studio | SIL OFL 1.1, `Geist-LICENSE.txt` |
| IBM Plex Mono | IBM | SIL OFL 1.1, `IBMPlexMono-LICENSE.txt` |
| Contributor Covenant | Code of Conduct v2.0, adapted from Skilli | Attribution and upstream link in `CODE_OF_CONDUCT.md` |

All app notices live in [Sources/dsmnapp/Resources](../Sources/dsmnapp/Resources)
and are copied into the Xcode app's `Contents/Resources`. Finder's Show Package
Contents provides access without running the app. Bundle verification checks that
these files match their source copies.

Raycast's first-party extension remains [MIT-licensed](../raycast/LICENSE), as
required by the [Raycast extension schema](https://www.raycast.com/schemas/extension.json).
Its npm dependencies
retain their own licenses. The lockfile records the resolved graph; a separate
Raycast distribution must include the notices required by the components it
actually redistributes. The native app does not bundle the Raycast npm tree.

## When changing dependencies or distributing builds

- Record provenance and preserve upstream notices for code, fonts, icons, and
  other assets. Do not remove upstream author credits as a privacy cleanup.
- Review license compatibility before adding a dependency.
- Update notices with dependency versions; do not rely on an upstream repository
  link in place of a required distributed notice.
- Keep `LICENSE` and bundled `dsmn-LICENSE.txt` identical.
- Provide corresponding source for distributed GPL binaries, including the
  applicable build scripts and license notices, tied to the released commit.
  See [GNU GPL v3](https://www.gnu.org/licenses/gpl-3.0.en.html).
- Verify the actual exported/downloaded app contains notices. Do not assume
  source-tree presence proves distribution compliance.
