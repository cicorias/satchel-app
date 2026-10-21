#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
# Build the browser extension: scripts/build/extension.sh [chrome|edge|safari] (default: all three).
target="${1:-all}"
case "$target" in
  all) pnpm --filter @satchel/extension build ;;
  chrome|edge|safari) pnpm --filter @satchel/extension "build:$target" ;;
  *) echo "usage: $0 [chrome|edge|safari]" >&2; exit 2 ;;
esac
