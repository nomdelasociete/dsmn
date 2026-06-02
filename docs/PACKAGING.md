# Packaging

`dsmn` uses `SMAppService` to register a privileged LaunchDaemon embedded inside
the main app bundle. The Debug build can compile and launch locally, but a real
helper install should be validated from an exported and notarized app.

## Archive

```sh
DSMN_SPARKLE_PUBLIC_ED_KEY=<public-key> ./scripts/archive.sh
```

By default this creates:

- `dist/dsmn.xcarchive`
- `dist/export/dsmn.app`

The export options use Developer ID distribution for team `JSFMAD28GS`. If the
Developer ID Application certificate is not installed, archive may succeed while
export fails. That is a signing setup issue, not an app build issue.

The archive script forces Release archive signing with manual
`Developer ID Application` settings for team `JSFMAD28GS`. The tool targets are
marked `SKIP_INSTALL=YES` so they are embedded inside `dsmn.app` without turning
the archive into a generic multi-product archive.

Release archives also require Sparkle update metadata. `DSMN_UPDATE_FEED_URL`
defaults to:

```text
https://dsmn.app/appcast.xml
```

Generate the Sparkle EdDSA key once with:

```sh
./scripts/sparkle_generate_keys.sh
```

The private key is stored in your login Keychain by Sparkle. Put the printed
public key in `DSMN_SPARKLE_PUBLIC_ED_KEY` when archiving. The scripts use the
Keychain account `nomdelasociete-dsmn` by default; set `SPARKLE_KEY_ACCOUNT` to
override it.

For normal releases, use the one-command publishing script instead:

```sh
./scripts/set_version.sh 0.1.1
git add project.yml macos/dsmn/Info.plist macos/DSMNCore/Info.plist
git commit -m "Bump dsmn to 0.1.1"
git push
./scripts/publish_release.sh
```

It reads the Sparkle public key from `DSMN_SPARKLE_PUBLIC_ED_KEY`, or from the
Keychain account when the variable is omitted.

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
- the embedded `dsmnctl` signature;
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

## Generate Appcast

After notarization, create the zip used by Sparkle and regenerate the appcast:

```sh
ditto -c -k --keepParent dist/export/dsmn.app dist/dsmn-notarized.zip
./scripts/generate_appcast.sh dist/dsmn-notarized.zip
```

This copies the archive into `dist/updates/` and runs Sparkle's
`generate_appcast` tool with the appcast URL set to
`https://dsmn.app/appcast.xml` and archive URLs under
`https://dsmn.app/download/`.

Upload `dist/updates/` through the website repo so the Railway service can serve
the files from its bucket-backed release routes:

```sh
cd /Users/jb/Documents/Github/NomDeLaSociete/dsmn-website
railway run npm run upload:release -- --dir /Users/jb/Documents/Github/NomDeLaSociete/dsmn/dist/updates
```

Override `DSMN_UPDATE_FEED_URL` and `DSMN_UPDATE_BASE_URL` only if the public
site moves away from `https://dsmn.app`.

`publish_release.sh` performs these steps automatically and fails before upload
if the exported app is missing `SUFeedURL`/`SUPublicEDKey` or if the appcast is
not signed with `sparkle:edSignature`.

It also reads the public appcast before archiving and refuses to publish when the
current source build number is not newer. Use `./scripts/set_version.sh` before
each release; set `DSMN_ALLOW_REPUBLISH=1` only when intentionally replacing the
same build.

## Self-Update State Contract

Sparkle may quit and relaunch the menu bar app, but it must not stop or renew a
dsmn timer. The current timer is preserved because runtime state lives outside
the app bundle in the helper store at `/Library/Application Support/dsmn`; the
local development fallback uses `~/.dsmn`. If the timer expires while the app is
being updated, the normal helper reconciliation path releases the power lock.

## Install Shape

For the production path:

1. Export and notarize `dsmn.app`.
2. Put `dsmn.app` in `/Applications`.
3. Launch the app and choose `Install Helper`.
4. Approve the helper in System Settings if macOS marks it as requiring approval.

The app should not write files directly into `/Library/LaunchDaemons`. It should
let `SMAppService` own registration and approval.
