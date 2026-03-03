#!/usr/bin/env bash
set -euo pipefail

PROJECT_PATH="${PROJECT_PATH:-AudioHapticGenerator.xcodeproj}"
SCHEME_NAME="${SCHEME_NAME:-AudioHapticGenerator}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$PWD/build/DerivedData}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$PWD/build/archive/AudioHapticGenerator.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$PWD/build/export}"
RUNNER_TEMP_DIR="${RUNNER_TEMP:-/tmp}"

required_vars=(
  IOS_CERTIFICATE_P12_BASE64
  IOS_CERTIFICATE_PASSWORD
  IOS_PROVISIONING_PROFILE_BASE64
  IOS_EXPORT_OPTIONS_BASE64
  IOS_KEYCHAIN_PASSWORD
  IOS_TEAM_ID
)

for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "Missing required environment variable: $var_name" >&2
    exit 1
  fi
done

decode_base64() {
  if base64 --decode </dev/null >/dev/null 2>&1; then
    base64 --decode
  else
    base64 -D
  fi
}

CERT_PATH="$RUNNER_TEMP_DIR/build_certificate.p12"
PROFILE_PATH="$RUNNER_TEMP_DIR/build_profile.mobileprovision"
PROFILE_PLIST_PATH="$RUNNER_TEMP_DIR/build_profile.plist"
EXPORT_OPTIONS_PATH="$RUNNER_TEMP_DIR/ExportOptions.plist"
KEYCHAIN_PATH="$RUNNER_TEMP_DIR/ci-signing.keychain-db"

cleanup() {
  security delete-keychain "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "$RUNNER_TEMP_DIR"
mkdir -p "$PWD/build/archive" "$PWD/build/export"

echo -n "$IOS_CERTIFICATE_P12_BASE64" | decode_base64 > "$CERT_PATH"
echo -n "$IOS_PROVISIONING_PROFILE_BASE64" | decode_base64 > "$PROFILE_PATH"
echo -n "$IOS_EXPORT_OPTIONS_BASE64" | decode_base64 > "$EXPORT_OPTIONS_PATH"

security create-keychain -p "$IOS_KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$IOS_KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$CERT_PATH" -P "$IOS_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
security set-key-partition-list -S apple-tool:,apple: -s -k "$IOS_KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security list-keychains -d user -s "$KEYCHAIN_PATH" login.keychain-db

security cms -D -i "$PROFILE_PATH" > "$PROFILE_PLIST_PATH"
PROFILE_UUID=$(/usr/libexec/PlistBuddy -c 'Print UUID' "$PROFILE_PLIST_PATH")
PROFILE_NAME=$(/usr/libexec/PlistBuddy -c 'Print Name' "$PROFILE_PLIST_PATH")

mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
cp "$PROFILE_PATH" "$HOME/Library/MobileDevice/Provisioning Profiles/$PROFILE_UUID.mobileprovision"

SIGNING_IDENTITY=$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/')
if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "Unable to find a code signing identity in imported certificate." >&2
  exit 1
fi

xcodegen generate

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME_NAME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$IOS_TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  PROVISIONING_PROFILE_SPECIFIER="$PROFILE_NAME" \
  archive

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PATH"

IPA_PATH=$(find "$EXPORT_PATH" -maxdepth 1 -name '*.ipa' -print -quit)
if [[ -z "$IPA_PATH" ]]; then
  echo "IPA export failed: no .ipa file found in $EXPORT_PATH" >&2
  exit 1
fi

echo "Created signed ipa: $IPA_PATH"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "ipa_path=$IPA_PATH" >> "$GITHUB_OUTPUT"
fi
