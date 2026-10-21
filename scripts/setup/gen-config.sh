#!/usr/bin/env bash
# Generate derived config from config/app.config.json (+ gitignored config/local.config.json).
set -euo pipefail
cd "$(dirname "$0")/../.."
exec node scripts/setup/gen-config.mjs "$@"
