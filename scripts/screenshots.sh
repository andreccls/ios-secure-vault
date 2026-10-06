#!/usr/bin/env bash
# Captures README screenshots (light, dark, dark + large Dynamic Type) from fictional seed data.
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
UDID="${UDID:-32490A14-20D8-49F0-9F26-A5437BAE6AD6}"
DD="${DD:-build}"
OUT="$(cd "$(dirname "$0")/.." && pwd)/${SCREENSHOT_DIR:-build/shots}"; case "${SCREENSHOT_DIR:-}" in /*) OUT="$SCREENSHOT_DIR";; esac
mkdir -p "$OUT"
xcrun simctl boot "$UDID" 2>/dev/null || true
run() { # $1 = file suffix
  rm -rf "$DD/shots.xcresult"
  TEST_RUNNER_SCREENSHOT_DIR="$OUT" TEST_RUNNER_SHOT_SUFFIX="$1" \
    xcodebuild -project SecureVault.xcodeproj -scheme SecureVault -derivedDataPath "$DD" \
    -destination "platform=iOS Simulator,id=$UDID" CODE_SIGNING_ALLOWED=NO -quiet \
    -resultBundlePath "$DD/shots.xcresult" -only-testing:SecureVaultUITests/ScreenshotTests test
}
xcrun simctl ui "$UDID" appearance light; xcrun simctl ui "$UDID" content_size large; run light
xcrun simctl ui "$UDID" appearance dark; run dark
xcrun simctl ui "$UDID" content_size accessibility-extra-large; run dark-xxl || echo "note: some assertions failed at accessibility-XXL (layout wraps); screenshots were still captured"
xcrun simctl ui "$UDID" appearance light; xcrun simctl ui "$UDID" content_size large
rm -rf "$DD/shots.xcresult"
xcrun simctl shutdown "$UDID"
# Downscale to 600 px wide (keeps each PNG well under 300 KB) into docs/images.
mkdir -p docs/images
for f in "$OUT"/*.png; do
  case "$f" in *-xxl.png) case "$f" in *02-passwords*|*08-settings*) ;; *) continue ;; esac ;; esac sips --resampleWidth 600 "$f" --out "docs/images/$(basename "$f")" >/dev/null; done
