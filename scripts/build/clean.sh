#!/usr/bin/env bash
# Remove build outputs: Xcode project + DerivedData, staged web assets, WXT/tsup/Turbo outputs.
#   DEPS=1  also remove node_modules (run `mise run setup` afterwards)
set -euo pipefail
cd "$(dirname "$0")/../.."

rm -rf apple/build apple/Staged apple/Satchel.xcodeproj \
  apps/extension/.output apps/extension/.wxt packages/*/dist .turbo
if [ "${DEPS:-0}" = "1" ]; then
  rm -rf node_modules apps/*/node_modules packages/*/node_modules scripts/art/node_modules
  echo "cleaned build outputs and dependencies"
else
  echo "cleaned build outputs"
fi
