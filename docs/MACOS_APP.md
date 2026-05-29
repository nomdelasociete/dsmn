# macOS App

`dsmn` is the current Xcode-hosted macOS menu bar app. `dsmn-app` remains
available as a SwiftPM development entrypoint.

It is intentionally menu-bar-only:

- no Dock icon;
- icon-only menu bar item;
- official SF Symbol for the menu bar status item;
- compact Coffee-style actions.

## Run locally

```sh
swift run dsmn-app
```

For the Xcode-built `.app` bundle:

```sh
./script/build_and_run.sh
```

The current app writes state through `DSMNCore`. It does not execute `pmset`
directly and does not install the privileged helper.

## Menu actions

- `Keep Awake 30m`
- `Keep Awake 90m`
- `Auto On` / `Auto Off`
- `Stop`
- `Refresh`
- `Quit`

## Next bundle step

The production app should be packaged as `dsmn.app` with:

- `LSUIElement` enabled;
- helper registration through `SMAppService`;
- signed helper embedded in the app bundle;
- final app icon asset separate from SF Symbols.

## Xcode project

`project.yml` is the source of truth for the Xcode project. Regenerate with:

```sh
xcodegen generate
```

The detected Apple Development team is `JSFMAD28GS` for `NOM DE LA SOCIETE`.
The generated Debug app is signed with the local Apple Development certificate.
