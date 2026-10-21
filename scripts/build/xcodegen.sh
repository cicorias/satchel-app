#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
# Regenerate derived config, then apple/Satchel.xcodeproj from apple/project.yml (ADR-0008).
scripts/setup/gen-config.sh >/dev/null
mkdir -p apple/Staged/safari-extension apple/Staged/web
xcodegen generate --spec apple/project.yml --quiet
echo "generated apple/Satchel.xcodeproj"
