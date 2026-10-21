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
team=$(node -p "require('./config/local.config.json').apple.developmentTeam")
sed "s/__TEAM_ID__/$team/" scripts/deploy/ExportOptions.plist > "$out/ExportOptions.plist"
xcodebuild -exportArchive -archivePath "$out/Satchel.xcarchive" \
  -exportOptionsPlist "$out/ExportOptions.plist" -exportPath "$out" -allowProvisioningUpdates
echo "exported: $(ls "$out"/*.ipa)"
