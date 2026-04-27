#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: scripts/create-unsigned-dmg.sh <version>"
  exit 1
fi

VERSION="$1"
APP_NAME="Baseline"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="$ROOT_DIR/.DerivedData"
BUILD_APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/${APP_NAME}.app"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$DIST_DIR/dmg-staging"
DMG_PATH="$DIST_DIR/${APP_NAME}-${VERSION}-unsigned.dmg"
VOLUME_NAME="${APP_NAME} ${VERSION}"

if [[ ! "$VERSION" =~ ^[0-9]+[.][0-9]+[.][0-9]+([-+][A-Za-z0-9._-]+)?$ ]]; then
  echo "Version must look like 0.1.0 or 0.1.0-beta.1"
  exit 1
fi

command -v tuist >/dev/null 2>&1 || {
  echo "Tuist is required. Install with: brew install tuist"
  exit 1
}

command -v hdiutil >/dev/null 2>&1 || {
  echo "hdiutil is required to create a DMG."
  exit 1
}

cd "$ROOT_DIR"

echo "Generating Xcode project"
TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open

echo "Building unsigned Release app"
xcodebuild \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  DEVELOPMENT_TEAM= \
  build

if [[ ! -d "$BUILD_APP_PATH" ]]; then
  echo "Build succeeded but app bundle was not found at $BUILD_APP_PATH"
  exit 1
fi

echo "Preparing DMG staging directory"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
ditto "$BUILD_APP_PATH" "$STAGING_DIR/${APP_NAME}.app"
ln -s /Applications "$STAGING_DIR/Applications"

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"

echo "Creating $DMG_PATH"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$STAGING_DIR"

echo "Created unsigned DMG:"
echo "$DMG_PATH"
echo
echo "SHA-256:"
shasum -a 256 "$DMG_PATH"
