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

# Optional: mirror when services.gradle.org is blocked (set GRADLE_DISTRIBUTION_URL in workflow).
WRAPPER_PROPS="gradle/wrapper/gradle-wrapper.properties"
if [[ -n "${GRADLE_DISTRIBUTION_URL:-}" && -f "$WRAPPER_PROPS" ]]; then
  echo "Patching distributionUrl in $WRAPPER_PROPS (mirror)"
  _tmp="$(mktemp)"
  GRADLE_DISTRIBUTION_URL="$GRADLE_DISTRIBUTION_URL" awk '
    /^distributionUrl=/ { print "distributionUrl=" ENVIRON["GRADLE_DISTRIBUTION_URL"]; next }
    { print }
  ' "$WRAPPER_PROPS" > "$_tmp" && mv "$_tmp" "$WRAPPER_PROPS"
fi

run_gradle() {
  ./gradlew assembleRelease --no-daemon "$@"
}

MAX_ATTEMPTS="${GRADLE_DOWNLOAD_RETRIES:-4}"
DELAY_SEC="${GRADLE_RETRY_DELAY_SEC:-20}"
attempt=1
gradle_rc=1
while [[ "$attempt" -le "$MAX_ATTEMPTS" ]]; do
  set +e
  run_gradle
  gradle_rc=$?
  set -e
  if [[ "$gradle_rc" -eq 0 ]]; then
    break
  fi
  if [[ "$attempt" -ge "$MAX_ATTEMPTS" ]]; then
    echo "Gradle failed after $MAX_ATTEMPTS attempts (exit $gradle_rc)" >&2
    exit "$gradle_rc"
  fi
  echo "Gradle attempt $attempt failed (exit $gradle_rc); retrying in ${DELAY_SEC}s..."
  sleep "$DELAY_SEC"
  attempt=$((attempt + 1))
  DELAY_SEC=$((DELAY_SEC + 10))
done

if [[ "$gradle_rc" -ne 0 ]]; then
  echo "Gradle did not complete successfully (exit $gradle_rc)" >&2
  exit "$gradle_rc"
fi

# Prefer .../apk/release/*.apk; fall back to any APK under outputs.
APK_SRC="$(find app/build/outputs/apk/release -maxdepth 3 -type f -name '*.apk' 2>/dev/null | head -1)"
if [[ -z "$APK_SRC" ]]; then
  APK_SRC="$(find app/build/outputs -type f -name '*.apk' 2>/dev/null | head -1)"
fi
if [[ -z "$APK_SRC" ]]; then
  echo "No release APK under app/build/outputs; listing tree:" >&2
  find app/build/outputs -type f 2>/dev/null | head -80 >&2 || true
  exit 1
fi

DEST_NAME="AIBot-android-${CHANNEL}-${TAG_NAME}.apk"
cp "$APK_SRC" "$DIST_DIR/$DEST_NAME"
echo "Built $DIST_DIR/$DEST_NAME"
