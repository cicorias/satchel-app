#!/usr/bin/env bash
# CI: select the newest Xcode installed on the runner (or XCODE_VERSION if set, e.g. "27.1").
set -euo pipefail
if [ -n "${XCODE_VERSION:-}" ]; then
  app="/Applications/Xcode_${XCODE_VERSION}.app"
else
  app=$(ls -d /Applications/Xcode*.app | sort -V | tail -1)
fi
sudo xcode-select -s "$app/Contents/Developer"
xcodebuild -version
