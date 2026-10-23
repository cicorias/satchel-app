#!/usr/bin/env bash
# App Store app preview: erase the simulator, set a clean status bar, record its screen while StorePreviewTests runs
# the tour, then cut the recording to 886×1920, at most 30 s (scripts/art/preview-video.swift).
#   SIM="iPhone 18 Pro Max"   KEEP=1  skip erasing
# Output: apple/build/preview/app-preview-886x1920.mp4 (not committed). Needs the network for the demo article.
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/run/sim-lib.sh

if [ "${KEEP:-0}" != "1" ]; then scripts/run/sim-reset.sh; fi
xcrun simctl boot "${udid}" 2>/dev/null || true
xcrun simctl bootstatus "${udid}" -b >/dev/null
xcrun simctl ui "${udid}" appearance light
xcrun simctl status_bar "${udid}" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

out="$(pwd)/apple/build/preview"
rm -rf "${out}"
mkdir -p "${out}"
now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }

xcrun simctl io "${udid}" recordVideo --codec=h264 --force "${out}/recording.mov" 2>"${out}/record.log" &
recorder=$!
trap 'kill -INT "${recorder}" 2>/dev/null || true; xcrun simctl status_bar "${udid}" clear 2>/dev/null || true' EXIT
for _ in $(seq 1 50); do
  grep -q "Recording started" "${out}/record.log" && break
  sleep 0.2
done
started=$(now)

# xcodebuild passes TEST_RUNNER_* variables to the test runner without the prefix.
TEST_RUNNER_SATCHEL_PREVIEW_DIR="${out}" ONLY=StorePreviewTests scripts/run/ios-ui-tests.sh

kill -INT "${recorder}"
wait "${recorder}" 2>/dev/null || true
trap 'xcrun simctl status_bar "${udid}" clear 2>/dev/null || true' EXIT
swift scripts/art/preview-video.swift "${out}/recording.mov" "${started}" "${out}/events.json" \
  "${out}/app-preview-886x1920.mp4"
