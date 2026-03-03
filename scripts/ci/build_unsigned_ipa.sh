#!/usr/bin/env bash
set -euo pipefail

PROJECT_PATH="${PROJECT_PATH:-HapticGen.xcodeproj}"
SCHEME_NAME="${SCHEME_NAME:-HapticGen}"
APP_BUNDLE_NAME="${APP_BUNDLE_NAME:-HapticGen.app}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$PWD/build/DerivedData}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-$PWD/build/artifacts}"
PACKAGE_ROOT="${PACKAGE_ROOT:-$PWD/build/unsigned-package}"

xcodegen generate

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME_NAME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release-iphoneos/$APP_BUNDLE_NAME"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app bundle not found at: $APP_PATH" >&2
  exit 1
fi

mkdir -p "$ARTIFACTS_DIR"
rm -rf "$PACKAGE_ROOT"
mkdir -p "$PACKAGE_ROOT/Payload"
cp -R "$APP_PATH" "$PACKAGE_ROOT/Payload/"

IPA_PATH="$ARTIFACTS_DIR/HapticGen-unsigned.ipa"
rm -f "$IPA_PATH"

(
  cd "$PACKAGE_ROOT"
  zip -qry "$IPA_PATH" Payload
)

echo "Created unsigned IPA package: $IPA_PATH"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "ipa_path=$IPA_PATH" >> "$GITHUB_OUTPUT"
fi
