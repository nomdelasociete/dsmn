# dsmn Raycast Extension

This extension is a remote control for `dsmn`.

It calls `dsmnctl` only. It must never call `pmset`, `sudo`, or implement its own
power-management logic.

## Local development

From the repo root:

```sh
swift build
cd raycast
npm install
npm run dev
```

By default the extension looks for:

```text
../.build/debug/dsmnctl
```

Set the `dsmnctl Path` preference when using an installed binary.

The current SVG assets are placeholders for extension development. The final app
menu bar icon should be selected from SF Symbols or drawn deliberately as a
native macOS asset.

