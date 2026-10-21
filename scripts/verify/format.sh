#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
# Apply formatting: Biome for TypeScript/JSON, swift-format for Swift.
pnpm exec biome check --write .
swift format format --in-place --recursive --configuration .swift-format apple/Satchel apple/SatchelShare apple/SatchelSafari apple/SatchelKit
