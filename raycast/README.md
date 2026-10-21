# dsmn Raycast Extension

This extension is a remote control for `dsmn`.

It calls `dsmnctl` only. It must never call `pmset`, `sudo`, or implement its own
power-management logic.

## Local development

From the repo root:

```sh
swift build
cd raycast
npm ci
npm run dev
```

By default the extension looks for `dsmnctl` in:

```text
/Applications/dsmn.app/Contents/Library/Helpers/dsmnctl
~/Applications/dsmn.app/Contents/Library/Helpers/dsmnctl
../.build/debug/dsmnctl
../DerivedData/Build/Products/Debug/dsmn.app/Contents/Library/Helpers/dsmnctl
```

Set the `dsmnctl Path` preference when using an installed binary.

The Raycast assets mirror the native app: the idle menu bar icon is the crown,
and the active icon is the reversed crown inside a circle.

## Contributing and license

Follow the repository's [contribution guide](../CONTRIBUTING.md). First-party
extension code retains its MIT license; see [LICENSE](LICENSE) and the
[third-party inventory](../docs/LICENSES.md). Earlier copies retain licenses
already granted. Dependencies retain their upstream licenses.
