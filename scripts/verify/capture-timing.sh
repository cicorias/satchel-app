#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
# Informational capture timing over fixtures/pages/ (spec §14 Phase 1). Prints a table; never fails on budget.
CAPTURE_TIMING=1 pnpm --filter @satchel/capture exec vitest run test/timing.test.ts --silent=false --reporter=dot
