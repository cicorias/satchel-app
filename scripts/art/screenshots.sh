#!/usr/bin/env bash
# App Store screenshots: erase the simulator, set a clean status bar, capture with StoreScreenshotTests, then
# composite the captures into the frames (scripts/art/screenshots.mjs) as store/app-store/screenshot-*.png.
#   SIM="iPhone 18 Pro Max"   KEEP=1  skip erasing (reuse what's on the simulator)
# Needs the network: the share-sheet shot loads site/demo/plain-text.html from GitHub Pages.
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/run/sim-lib.sh

if [ "${KEEP:-0}" != "1" ]; then scripts/run/sim-reset.sh; fi
xcrun simctl boot "${udid}" 2>/dev/null || true
xcrun simctl bootstatus "${udid}" -b >/dev/null
xcrun simctl ui "${udid}" appearance light
xcrun simctl status_bar "${udid}" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
trap 'xcrun simctl status_bar "${udid}" clear 2>/dev/null || true' EXIT

out="$(pwd)/apple/build/screenshots"
rm -rf "${out}"
mkdir -p "${out}"
# xcodebuild passes TEST_RUNNER_* variables to the test runner without the prefix.
TEST_RUNNER_SATCHEL_SCREENSHOT_DIR="${out}" ONLY=StoreScreenshotTests scripts/run/ios-ui-tests.sh
node scripts/art/screenshots.mjs
