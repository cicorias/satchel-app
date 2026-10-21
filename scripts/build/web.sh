#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
# Build every web package and all extension targets (cached by Turborepo).
pnpm turbo run build "$@"
