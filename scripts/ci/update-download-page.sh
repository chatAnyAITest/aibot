#!/usr/bin/env bash
set -euo pipefail

: "${TAG_NAME:?TAG_NAME is required}"
: "${VERSION:?VERSION is required}"
: "${CHANNEL:?CHANNEL is required}"
: "${BUNDLE_ID:?BUNDLE_ID is required}"
: "${DISPLAY_NAME:?DISPLAY_NAME is required}"
: "${IPA_URL:=}"
: "${APK_URL:=}"

DATE="$(date -u +%Y-%m-%d)"

mkdir -p docs

cat > docs/release.json <<EOF
{
  "tag_name": "${TAG_NAME}",
  "version": "${VERSION}",
  "channel": "${CHANNEL}",
  "app_display_name": "${DISPLAY_NAME}",
  "bundle_identifier": "${BUNDLE_ID}",
  "ipa_url": "${IPA_URL}",
  "apk_url": "${APK_URL}",
  "date": "${DATE}"
}
EOF

cat > docs/manifest.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>items</key>
  <array>
    <dict>
      <key>assets</key>
      <array>
        <dict>
          <key>kind</key>
          <string>software-package</string>
          <key>url</key>
          <string>${IPA_URL}</string>
        </dict>
      </array>
      <key>metadata</key>
      <dict>
        <key>bundle-identifier</key>
        <string>${BUNDLE_ID}</string>
        <key>bundle-version</key>
        <string>${VERSION}</string>
        <key>kind</key>
        <string>software</string>
        <key>title</key>
        <string>${DISPLAY_NAME}</string>
      </dict>
    </dict>
  </array>
</dict>
</plist>
EOF

echo "Updated docs/release.json and docs/manifest.plist for ${TAG_NAME}"
