#!/usr/bin/env bash
# Build Satchel, then install and launch it on an iOS simulator.
#   SIM="iPhone 18 Pro Max"  device name (default); any name from `xcrun simctl list devices available`
#   LOGS=1                   stay attached and stream the app's stdout/stderr (Ctrl-C to stop)
set -euo pipefail
cd "$(dirname "$0")/../.."

source scripts/run/sim-lib.sh

echo "simulator: $sim ($udid)"
xcrun simctl boot "$udid" 2>/dev/null || true # already booted is fine
# Show the device window: Simulator.app on older Xcodes, DeviceHub on Xcode 27+. Non-fatal — the app
# still runs headless (use `xcrun simctl io booted screenshot shot.png` to see it).
open -b com.apple.iphonesimulator --args -CurrentDeviceUDID "$udid" 2>/dev/null ||
  open -b com.apple.dt.Devices 2>/dev/null ||
  echo "note: no simulator UI app found; running headless"
xcrun simctl bootstatus "$udid" -b >/dev/null

DESTINATION="id=$udid" scripts/build/ios.sh
xcrun simctl install "$udid" apple/build/DerivedData/Build/Products/Debug-iphonesimulator/Satchel.app

if [ "${LOGS:-0}" = "1" ]; then
  exec xcrun simctl launch --console-pty --terminate-running-process "$udid" "$bundle_id"
fi
xcrun simctl launch --terminate-running-process "$udid" "$bundle_id"
