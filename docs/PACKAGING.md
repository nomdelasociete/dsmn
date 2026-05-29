# Packaging

`dsmn` uses `SMAppService` to register a privileged LaunchDaemon embedded inside
the main app bundle. The Debug build can compile and launch locally, but a real
helper install should be validated from an exported and notarized app.

## Archive

```sh
./scripts/archive.sh
```

By default this creates:

- `dist/dsmn.xcarchive`
- `dist/export/dsmn.app`

The export options use Developer ID distribution for team `JSFMAD28GS`. If the
Developer ID Application certificate is not installed, archive may succeed while
export fails. That is a signing setup issue, not an app build issue.

To archive without exporting:

```sh
EXPORT=0 ./scripts/archive.sh
```

## Verify Bundle

```sh
./scripts/verify_bundle.sh dist/export/dsmn.app
```

This checks:

- the app signature;
- the embedded `dsmnd` signature;
- the LaunchDaemon plist at `Contents/Library/LaunchDaemons`;
- the plist structure.

## Notarize

Create a notarytool keychain profile once:

```sh
xcrun notarytool store-credentials <profile-name>
```

Then submit and staple:

```sh
AC_NOTARY_PROFILE=<profile-name> ./scripts/notarize.sh dist/export/dsmn.app
```

The script zips the app with `ditto`, submits with `notarytool`, staples the
ticket to the app, validates the stapled ticket, then runs `spctl`.

## Install Shape

For the production path:

1. Export and notarize `dsmn.app`.
2. Put `dsmn.app` in `/Applications`.
3. Launch the app and choose `Install Helper`.
4. Approve the helper in System Settings if macOS marks it as requiring approval.

The app should not write files directly into `/Library/LaunchDaemons`. It should
let `SMAppService` own registration and approval.
