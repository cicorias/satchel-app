#!/usr/bin/env bash
# Render all icons and store artwork from art/src/satchel.mjs (see scripts/art/render.mjs).
set -euo pipefail
cd "$(dirname "$0")/../.."
exec node scripts/art/render.mjs "$@"
