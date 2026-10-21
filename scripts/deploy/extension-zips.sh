#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
# Store zips for Chrome Web Store and Edge Add-ons (written to apps/extension/.output/).
pnpm --filter @satchel/extension zip
ls apps/extension/.output/*.zip
