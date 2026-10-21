#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
# One-time (and idempotent) developer setup.
mise install
pnpm install
scripts/setup/install-hooks.sh
scripts/setup/gen-config.sh
echo "Setup complete. Try: mise run verify && mise run build:ios"
