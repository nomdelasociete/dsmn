#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-}"
BUILD="${2:-}"

if [[ -z "$VERSION" || "$VERSION" == "-h" || "$VERSION" == "--help" ]]; then
  echo "usage: ./scripts/set_version.sh <marketing-version> [build-number]" >&2
  echo "example: ./scripts/set_version.sh 0.1.1" >&2
  exit 2
fi

if [[ ! "$VERSION" =~ ^[0-9]+([.][0-9]+){1,2}$ ]]; then
  echo "invalid marketing version: $VERSION" >&2
  exit 2
fi

if [[ -z "$BUILD" ]]; then
  current_build="$(plutil -extract CFBundleVersion raw -o - "$ROOT_DIR/macos/dsmn/Info.plist")"
  BUILD="$((current_build + 1))"
fi

if [[ ! "$BUILD" =~ ^[0-9]+$ ]]; then
  echo "invalid build number: $BUILD" >&2
  exit 2
fi

for plist in "$ROOT_DIR/macos/dsmn/Info.plist" "$ROOT_DIR/macos/DSMNCore/Info.plist"; do
  plutil -replace CFBundleShortVersionString -string "$VERSION" "$plist"
  plutil -replace CFBundleVersion -string "$BUILD" "$plist"
done

perl -0pi -e 's/(CFBundleShortVersionString:\s*")[^"]+(")/${1}'"$VERSION"'$2/g; s/(CFBundleVersion:\s*")[^"]+(")/${1}'"$BUILD"'$2/g' "$ROOT_DIR/project.yml"

echo "Set dsmn version to $VERSION ($BUILD)"
