#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
# Regenerate derived config, then apple/Satchel.xcodeproj from apple/project.yml (ADR-0008).
scripts/setup/gen-config.sh >/dev/null
mkdir -p apple/Staged/safari-extension apple/Staged/web
# --use-cache skips the rewrite when project.yml and the file list are unchanged, so an open Xcode
# doesn't reload needlessly. FORCE=1 regenerates anyway.
if [ "${FORCE:-0}" = "1" ]; then
  xcodegen generate --spec apple/project.yml --quiet
else
  xcodegen generate --spec apple/project.yml --quiet --use-cache
fi
echo "generated apple/Satchel.xcodeproj"
