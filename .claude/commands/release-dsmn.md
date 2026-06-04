---
description: Publish a new signed dsmn release from main
argument-hint: "[version] [build]"
allowed-tools: Bash, Read, Edit, Grep
---

Release dsmn from `main` after a merge or push.

User-supplied arguments: `$ARGUMENTS`

Parse `$ARGUMENTS` as:

- optional marketing version, for example `0.1.16`.
- optional build number, for example `17`.

If no version is provided, infer the next patch version from `project.yml` and
increment the current build by one. State the inferred version/build before
changing files.

Follow this runbook exactly:

1. Start clean and current.

   ```sh
   git fetch --all --prune
   git status --short --branch
   git checkout main
   git pull --ff-only origin main
   git status --short --branch
   ```

   Stop if the worktree has unrelated changes. Do not release from a stale
   branch or a detached worktree.

2. Ensure generated local plists exist, then run the normal test suite.

   ```sh
   xcodegen generate --use-cache
   swift test
   ```

   If `xcodegen` changes `dsmn.xcodeproj/project.pbxproj`, inspect the diff.
   The known harmless churn is the generated embed-phase swap between
   `Contents/Library/Helpers` and `Contents/Library/LaunchDaemons`. Restore that
   generated churn before committing. Stop for review on any other project-file
   change.

3. Bump the source version.

   ```sh
   ./scripts/set_version.sh <version> [build]
   xcodegen generate --use-cache
   ```

   Verify all three version sources agree:

   ```sh
   rg -n 'CFBundleShortVersionString|CFBundleVersion' project.yml
   plutil -extract CFBundleShortVersionString raw -o - macos/dsmn/Info.plist
   plutil -extract CFBundleVersion raw -o - macos/dsmn/Info.plist
   plutil -extract CFBundleShortVersionString raw -o - macos/DSMNCore/Info.plist
   plutil -extract CFBundleVersion raw -o - macos/DSMNCore/Info.plist
   ```

   The `macos/*/Info.plist` files are generated and ignored; do not add them.
   Commit only tracked release metadata unless another tracked file changed for
   a deliberate reason.

4. Commit and push the version bump.

   ```sh
   git status --short --branch
   git add project.yml
   git commit -m "Bump dsmn to <version>"
   git push origin main
   ```

5. Publish the release.

   ```sh
   ./scripts/publish_release.sh
   ```

   Do not claim success from a local archive. The publish script must complete
   Apple notarization, staple the app and DMG, generate the signed Sparkle
   appcast, and upload through the `dsmn-website` Railway release path.

6. Verify public artifacts, not local `dist/export`.

   ```sh
   curl -fsSL https://dsmn.app/appcast.xml -o /tmp/dsmn-appcast.xml
   xmllint --xpath 'string(//*[local-name()="shortVersionString"])' /tmp/dsmn-appcast.xml
   xmllint --xpath 'string(//*[local-name()="version"])' /tmp/dsmn-appcast.xml

   curl -fsSI https://dsmn.app/download/dsmn-latest.zip
   curl -fsSI https://dsmn.app/download/dsmn-latest.dmg
   ```

   Then verify the shipped ZIP:

   ```sh
   workdir="$(mktemp -d)"
   curl -fsSL -o "$workdir/dsmn-latest.zip" https://dsmn.app/download/dsmn-latest.zip
   ditto -x -k "$workdir/dsmn-latest.zip" "$workdir/unzip"
   app="$workdir/unzip/dsmn.app"
   /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist"
   /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist"
   codesign -v --deep --strict "$app"
   codesign -dv "$app/Contents/Library/Helpers/dsmnctl" 2>&1 | grep -E 'Identifier|TeamIdentifier'
   codesign -dv "$app/Contents/Library/LaunchDaemons/dsmnd" 2>&1 | grep -E 'Identifier|TeamIdentifier'
   spctl -a -vv --type execute "$app"
   rm -rf "$workdir"
   ```

   Expected nested identifiers:

   ```text
   dsmnctl: com.nomdelasociete.dsmn.dsmnctl
   dsmnd: com.nomdelasociete.dsmn.helper
   TeamIdentifier: JSFMAD28GS
   ```

   Verify the public DMG:

   ```sh
   workdir="$(mktemp -d)"
   curl -fsSL -o "$workdir/dsmn-latest.dmg" https://dsmn.app/download/dsmn-latest.dmg
   hdiutil verify "$workdir/dsmn-latest.dmg"
   rm -rf "$workdir"
   ```

7. Finish with repository and release state.

   ```sh
   git status --short --branch
   git rev-list --left-right --count main...origin/main
   ```

   Final response must include the released version/build, pushed commit(s),
   test result, public appcast/ZIP/DMG verification, and any issue that prevented
   publication. Do not say the release is done unless the public artifacts match
   the requested version/build.
