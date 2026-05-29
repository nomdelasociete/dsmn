# macOS App

`dsmn` is the current Xcode-hosted macOS menu bar app. `dsmn-app` remains
available as a SwiftPM development entrypoint.

It is intentionally menu-bar-only:

- no Dock icon;
- icon-only menu bar item;
- official SF Symbol for the menu bar status item;
- compact Coffee-style actions.

The menu bar symbol changes by state:

- `figure.run`: off or loading;
- `figure.run.circle`: auto armed, waiting for an agent;
- `figure.run.circle.fill`: auto actively preventing sleep;
- `timer.circle.fill`: manual timer actively preventing sleep;
- `exclamationmark.triangle`: status unavailable before any report is loaded.

## Run locally

```sh
swift run dsmn-app
```

For the Xcode-built `.app` bundle:

```sh
./script/build_and_run.sh
```

The app writes state through `DSMNCore` in development mode. In the Xcode-built
bundle, it also embeds the helper executable and LaunchDaemon plist and can ask
`SMAppService` to register or unregister the helper.

## Menu actions

- `Keep Awake 30m`
- `Keep Awake 90m`
- `Auto On` / `Auto Off`
- `Stop`
- `Refresh`
- `Install Helper`
- `Open Login Items`
- `Unregister Helper`
- `Quit`

## Next bundle step

The production app is packaged as `dsmn.app` with:

- `LSUIElement` enabled;
- helper registration through `SMAppService`;
- signed helper embedded in the app bundle;
- final app icon asset separate from SF Symbols.

Still required for a production install:

- copy the archived app to `/Applications`;
- notarize the app before relying on LaunchDaemon registration;
- approve the helper in System Settings when macOS requests it.

## Xcode project

`project.yml` is the source of truth for the Xcode project. Regenerate with:

```sh
xcodegen generate
```

The detected Apple Development team is `JSFMAD28GS` for `NOM DE LA SOCIETE`.
The generated Debug app is signed with the local Apple Development certificate.
