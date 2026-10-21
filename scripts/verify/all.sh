#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
# Everything CI checks. Apple checks run only on macOS.
scripts/verify/secrets.sh
scripts/verify/web.sh
if [ "$(uname)" = "Darwin" ]; then scripts/verify/apple.sh; fi
