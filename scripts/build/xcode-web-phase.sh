#!/usr/bin/env bash
# Xcode "WebAssets" build phase. Xcode runs scripts with a minimal PATH, so locate mise first.
set -euo pipefail
repo="$(cd "${SRCROOT:?run from an Xcode build phase (SRCROOT is set by Xcode)}/.." && pwd)"
for candidate in "$(command -v mise || true)" "$HOME/.local/bin/mise" /opt/homebrew/bin/mise /usr/local/bin/mise; do
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then mise="$candidate"; break; fi
done
if [ -z "${mise:-}" ]; then
  echo "error: mise not found; install it (https://mise.jdx.dev) and run 'mise run setup'" >&2
  exit 1
fi
cd "$repo"
exec "$mise" exec -- scripts/build/web-for-apple.sh
