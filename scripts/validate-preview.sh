#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Baseline"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="$ROOT_DIR/.DerivedData"
INSTALL_PATH="/Applications/${APP_NAME}.app"
VERSION="${1:-0.0.0-preview}"

cd "$ROOT_DIR"

stop_existing_app() {
  if ! pgrep -x "$APP_NAME" >/dev/null; then
    return
  fi

  echo "Stopping existing ${APP_NAME} process"
  osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true

  for _ in {1..20}; do
    if ! pgrep -x "$APP_NAME" >/dev/null; then
      return
    fi
    sleep 0.25
  done

  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  for _ in {1..20}; do
    if ! pgrep -x "$APP_NAME" >/dev/null; then
      return
    fi
    sleep 0.25
  done

  echo "Could not stop existing ${APP_NAME} process before smoke launch."
  exit 1
}

echo "Checking generated artifacts are ignored"
for ignored_path in "${APP_NAME}.xcodeproj" "${APP_NAME}.xcworkspace" ".DerivedData" "Derived" "dist"; do
  git check-ignore -q "$ignored_path" || {
    echo "Expected $ignored_path to be ignored."
    exit 1
  }
done

echo "Linting scripts"
bash -n scripts/create-unsigned-dmg.sh
bash -n scripts/prepare-unsigned-release.sh
bash -n scripts/validate-preview.sh

echo "Generating Xcode project"
TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open

echo "Building Debug app"
TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

echo "Running unit tests"
xcodebuild \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "$APP_NAME" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  test

echo "Creating unsigned preview DMG"
scripts/create-unsigned-dmg.sh "$VERSION"

DEBUG_APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/${APP_NAME}.app"
if [[ ! -d "$DEBUG_APP_PATH" ]]; then
  echo "Debug app bundle was not found at $DEBUG_APP_PATH"
  exit 1
fi

echo "Installing Debug app to $INSTALL_PATH"
stop_existing_app
rm -rf "$INSTALL_PATH"
ditto "$DEBUG_APP_PATH" "$INSTALL_PATH"

echo "Launching installed app"
open "$INSTALL_PATH"

for _ in {1..20}; do
  if pgrep -x "$APP_NAME" >/dev/null; then
    echo "Smoke launch succeeded."
    echo "Known-good preview validation completed."
    exit 0
  fi
  sleep 0.25
done

echo "Smoke launch failed; ${APP_NAME} process was not detected."
exit 1
