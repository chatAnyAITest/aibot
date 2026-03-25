#!/usr/bin/env bash
# CI iOS archive + export for askchance/aibot mobile app.
# Run with cwd = aibot-source/mobile (same env contract as heartie-ci workflows).
set -euo pipefail

VERSION="${1:?version required}"
BUILD_NUMBER="${2:?build number required}"
TAG_NAME="${3:?tag name required}"

MOBILE_ROOT="$(pwd)"
IOS_DIR="$MOBILE_ROOT/ios"
SCHEME="mobile"
WORKSPACE="$IOS_DIR/mobile.xcworkspace"
PROJECT="$IOS_DIR/mobile.xcodeproj"
PBXPROJ="$PROJECT/project.pbxproj"
BUILD_ROOT="$MOBILE_ROOT/build/ios/$TAG_NAME"
DIST_DIR="$MOBILE_ROOT/dist/ios/$TAG_NAME"
LOG_FILE="$BUILD_ROOT/xcodebuild-archive.log"
KEYCHAIN="${KEYCHAIN:-$BUILD_ROOT/aibot-ci.keychain-db}"

mkdir -p "$BUILD_ROOT" "$DIST_DIR"

CHANNEL="${IOS_BUILD_CHANNEL:-prod}"
if [[ "$CHANNEL" == "test" ]]; then
  P12_B64="${IOS_TEST_CERTIFICATE_P12_BASE64:-${IOS_CERTIFICATE_P12_BASE64:-}}"
  CERT_PASSWORD="${IOS_TEST_CERTIFICATE_PASSWORD:-${IOS_CERTIFICATE_PASSWORD:-}}"
  PROFILE_B64="${IOS_TEST_PROVISIONING_PROFILE_BASE64:-${IOS_PROVISIONING_PROFILE_BASE64:-}}"
  TEAM_ID="${IOS_TEST_TEAM_ID:-${IOS_TEAM_ID:-}}"
else
  P12_B64="${IOS_PROD_CERTIFICATE_P12_BASE64:-${IOS_CERTIFICATE_P12_BASE64:-}}"
  CERT_PASSWORD="${IOS_PROD_CERTIFICATE_PASSWORD:-${IOS_CERTIFICATE_PASSWORD:-}}"
  PROFILE_B64="${IOS_PROD_PROVISIONING_PROFILE_BASE64:-${IOS_PROVISIONING_PROFILE_BASE64:-}}"
  TEAM_ID="${IOS_PROD_TEAM_ID:-${IOS_TEAM_ID:-}}"
fi

if [[ -z "$P12_B64" || -z "$CERT_PASSWORD" || -z "$PROFILE_B64" || -z "$TEAM_ID" ]]; then
  echo "Missing iOS signing inputs for channel=$CHANNEL (P12 / password / profile / team)" >&2
  exit 1
fi

BUNDLE_ID="${IOS_BUNDLE_IDENTIFIER:-}"
DISPLAY_NAME="${IOS_APP_DISPLAY_NAME:-}"
EXPORT_METHOD="${IOS_EXPORT_METHOD:-app-store}"
CODE_SIGN_IDENTITY="${IOS_CODE_SIGN_IDENTITY:-Apple Distribution}"

cleanup() {
  if [[ -f "$KEYCHAIN" ]]; then
    security delete-keychain "$KEYCHAIN" 2>/dev/null || true
  fi
}
trap cleanup EXIT

perl -i -pe "s/MARKETING_VERSION = [^;]+/MARKETING_VERSION = $VERSION/g" "$PBXPROJ"
perl -i -pe "s/CURRENT_PROJECT_VERSION = [^;]+/CURRENT_PROJECT_VERSION = $BUILD_NUMBER/g" "$PBXPROJ"
if [[ -n "$BUNDLE_ID" ]]; then
  perl -i -pe "s/PRODUCT_BUNDLE_IDENTIFIER = [^;]+/PRODUCT_BUNDLE_IDENTIFIER = $BUNDLE_ID/g" "$PBXPROJ"
else
  BUNDLE_ID="$(perl -ne 'print $1 if /PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);/ && !$seen++' "$PBXPROJ" | tr -d ' ')"
fi

INFO_PLIST="$IOS_DIR/mobile/Info.plist"
if [[ -n "$DISPLAY_NAME" ]]; then
  _ESC="${DISPLAY_NAME//\"/\\\"}"
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName \"${_ESC}\"" "$INFO_PLIST"
fi

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

bundle install
(
  cd "$IOS_DIR"
  bundle exec pod install
)

if [[ ! -d "$WORKSPACE" ]]; then
  echo "Expected workspace at $WORKSPACE after pod install" >&2
  exit 1
fi

KEYCHAIN_PASS="$(openssl rand -base64 32)"
security delete-keychain "$KEYCHAIN" 2>/dev/null || true
security create-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
security list-keychains -d user -s "$KEYCHAIN" "${HOME}/Library/Keychains/login.keychain-db"
security default-keychain -s "$KEYCHAIN"

decode64() { base64 -d 2>/dev/null || base64 --decode 2>/dev/null || base64 -D; }
echo "$P12_B64" | decode64 >"$BUILD_ROOT/cert.p12"
security import "$BUILD_ROOT/cert.p12" -k "$KEYCHAIN" -P "$CERT_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASS" "$KEYCHAIN"

echo "$PROFILE_B64" | decode64 >"$BUILD_ROOT/profile.mobileprovision"
security cms -D -i "$BUILD_ROOT/profile.mobileprovision" >"$BUILD_ROOT/profile.plist"
PROFILE_UUID="$(/usr/libexec/PlistBuddy -c 'Print UUID' "$BUILD_ROOT/profile.plist")"
PROFILE_NAME="$(/usr/libexec/PlistBuddy -c 'Print Name' "$BUILD_ROOT/profile.plist")"
PROFILE_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$PROFILE_DIR"
cp "$BUILD_ROOT/profile.mobileprovision" "$PROFILE_DIR/${PROFILE_UUID}.mobileprovision"

ARCHIVE_PATH="$BUILD_ROOT/mobile.xcarchive"
EXPORT_PLIST="$BUILD_ROOT/ExportOptions.plist"

cat >"$EXPORT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>${EXPORT_METHOD}</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>${BUNDLE_ID}</key>
    <string>${PROFILE_NAME}</string>
  </dict>
  <key>stripSwiftSymbols</key>
  <true/>
</dict>
</plist>
EOF

set +e
xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
  CODE_SIGN_STYLE=Manual \
  PROVISIONING_PROFILE_SPECIFIER="$PROFILE_NAME" \
  archive 2>&1 | tee "$LOG_FILE"
ARCHIVE_RC="${PIPESTATUS[0]}"
set -e
if [[ "$ARCHIVE_RC" -ne 0 ]]; then
  exit "$ARCHIVE_RC"
fi

set +e
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$DIST_DIR" \
  -exportOptionsPlist "$EXPORT_PLIST" 2>&1 | tee -a "$LOG_FILE"
EXPORT_RC="${PIPESTATUS[0]}"
set -e
if [[ "$EXPORT_RC" -ne 0 ]]; then
  exit "$EXPORT_RC"
fi

IPA_SRC="$(find "$DIST_DIR" -maxdepth 1 -name '*.ipa' -type f | head -1)"
if [[ -z "$IPA_SRC" ]]; then
  echo "No IPA produced under $DIST_DIR" >&2
  exit 1
fi

DEST_NAME="AIBot-ios-${CHANNEL}-${TAG_NAME}.ipa"
mv "$IPA_SRC" "$DIST_DIR/$DEST_NAME"
echo "Built $DIST_DIR/$DEST_NAME"
