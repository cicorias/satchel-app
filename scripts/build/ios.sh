#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
# Build the iOS app for the simulator. Unsigned by default so it works before portal setup;
# set SIGNED=1 to use automatic signing with the team from config/local.config.json.
scripts/build/xcodegen.sh
destination="${DESTINATION:-generic/platform=iOS Simulator}"
signing=(CODE_SIGNING_ALLOWED=NO)
[ "${SIGNED:-0}" = "1" ] && signing=(-allowProvisioningUpdates)
xcodebuild build \
  -project apple/Satchel.xcodeproj -scheme Satchel -configuration Debug \
  -destination "$destination" -derivedDataPath apple/build/DerivedData \
  "${signing[@]}" -quiet
echo "built Satchel.app -> apple/build/DerivedData/Build/Products/Debug-iphonesimulator/"
