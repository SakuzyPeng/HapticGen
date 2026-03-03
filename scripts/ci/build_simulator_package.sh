#!/usr/bin/env bash
set -euo pipefail

PROJECT_PATH="${PROJECT_PATH:-HapticGen.xcodeproj}"
SCHEME_NAME="${SCHEME_NAME:-HapticGen}"
APP_BUNDLE_NAME="${APP_BUNDLE_NAME:-HapticGen.app}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$PWD/build/DerivedData}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-$PWD/build/artifacts}"

xcodegen generate

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME_NAME" \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release-iphonesimulator/$APP_BUNDLE_NAME"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app bundle not found at: $APP_PATH" >&2
  exit 1
fi

mkdir -p "$ARTIFACTS_DIR"
ZIP_PATH="$ARTIFACTS_DIR/HapticGen-simulator-app.zip"
rm -f "$ZIP_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Created simulator package: $ZIP_PATH"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "zip_path=$ZIP_PATH" >> "$GITHUB_OUTPUT"
fi
