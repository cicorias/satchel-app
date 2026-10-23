#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
# Build the iOS app for the simulator. Ad-hoc signed by default ("-": no certificate or team needed), which still
# embeds the entitlements, so the App Group and iCloud keys work on the simulator. SIGNED=1 uses automatic signing
# with the team from config/local.config.json (device builds).
scripts/build/xcodegen.sh
destination="${DESTINATION:-generic/platform=iOS Simulator}"
signing=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
[ "${SIGNED:-0}" = "1" ] && signing=(-allowProvisioningUpdates)
xcodebuild build \
  -project apple/Satchel.xcodeproj -scheme Satchel -configuration Debug \
  -destination "$destination" -derivedDataPath apple/build/DerivedData \
  "${signing[@]}" -quiet
echo "built Satchel.app -> apple/build/DerivedData/Build/Products/Debug-iphonesimulator/"
