#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
# Use the committed hooks in .githooks/ (secret scanning on commit; ADR-0014).
git config core.hooksPath .githooks
echo "git hooks: core.hooksPath -> .githooks"
