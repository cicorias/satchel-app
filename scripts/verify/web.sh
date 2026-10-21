#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
# Lint (Biome), typecheck, and test the TypeScript workspace.
pnpm exec biome ci .
pnpm turbo run build typecheck test --output-logs=errors-only
