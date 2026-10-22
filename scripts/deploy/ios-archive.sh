#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
# Archive and export a signed iOS build for App Store Connect (ADR-0016).
# Requires: the portal setup in docs/setup/apple.md and config/local.config.json with the Team ID.
scripts/build/xcodegen.sh
out=apple/build/release
rm -rf "$out" && mkdir -p "$out"
xcodebuild archive \
  -project apple/Satchel.xcodeproj -scheme Satchel -configuration Release \
  -destination "generic/platform=iOS" -archivePath "$out/Satchel.xcarchive" \
  -allowProvisioningUpdates
# iPhone only (ADR-0011): an iPad family here gets the upload rejected (ITMS-90474), so fail now instead.
family=$(/usr/libexec/PlistBuddy -c "Print :UIDeviceFamily" "$out/Satchel.xcarchive/Products/Applications/Satchel.app/Info.plist" | tr -dc '0-9')
if [ "$family" != 1 ]; then
  echo "error: archived UIDeviceFamily is '$family', expected 1 (iPhone only); see settingGroups in apple/project.yml" >&2
  exit 1
fi
team=$(node -p "require('./config/local.config.json').apple.developmentTeam")
sed "s/__TEAM_ID__/$team/" scripts/deploy/ExportOptions.plist > "$out/ExportOptions.plist"
xcodebuild -exportArchive -archivePath "$out/Satchel.xcarchive" \
  -exportOptionsPlist "$out/ExportOptions.plist" -exportPath "$out" -allowProvisioningUpdates
echo "exported: $(ls "$out"/*.ipa)"
