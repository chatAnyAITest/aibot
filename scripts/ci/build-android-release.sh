#!/usr/bin/env bash
# CI Android assembleRelease for askchance/aibot mobile app.
# Run with cwd = aibot-source/mobile.
# Release signing follows android/app/build.gradle; add a release keystore + signingConfigs when ready.
set -euo pipefail

VERSION="${1:?version required}"
BUILD_NUMBER="${2:?build number required}"
TAG_NAME="${3:?tag name required}"

MOBILE_ROOT="$(pwd)"
ANDROID_DIR="$MOBILE_ROOT/android"
GRADLE_FILE="$ANDROID_DIR/app/build.gradle"
DIST_DIR="$MOBILE_ROOT/dist/android/$TAG_NAME"
CHANNEL="${ANDROID_BUILD_CHANNEL:-prod}"

mkdir -p "$DIST_DIR"

if [[ ! -f "$GRADLE_FILE" ]]; then
  echo "Missing $GRADLE_FILE" >&2
  exit 1
fi

perl -i -pe 's/versionCode \d+/versionCode '"$BUILD_NUMBER"'/' "$GRADLE_FILE"
perl -i -pe 's/versionName "[^"]*"/versionName "'"$VERSION"'"/' "$GRADLE_FILE"

cd "$ANDROID_DIR"
chmod +x ./gradlew
./gradlew assembleRelease --no-daemon

APK_SRC="$(find app/build/outputs/apk/release -maxdepth 1 -name '*.apk' -type f | head -1)"
if [[ -z "$APK_SRC" ]]; then
  echo "No release APK found under app/build/outputs/apk/release" >&2
  exit 1
fi

DEST_NAME="AIBot-android-${CHANNEL}-${TAG_NAME}.apk"
cp "$APK_SRC" "$DIST_DIR/$DEST_NAME"
echo "Built $DIST_DIR/$DEST_NAME"
