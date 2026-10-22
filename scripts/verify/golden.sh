#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
# Golden capture tests over fixtures/pages/ (spec §12.4). `-u` rewrites every expected.md from the current
# output; review the diff before committing. expected-metadata.json is written by hand and never updated.
if [ "${1:-}" = "-u" ]; then
  export UPDATE_GOLDEN=1
fi
pnpm --filter @satchel/capture exec vitest run test/golden.test.ts
