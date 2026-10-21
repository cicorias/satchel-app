#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
# Lint Swift with swift-format, then run SatchelKit tests on the host.
swift format lint --strict --recursive --configuration .swift-format apple/Satchel apple/SatchelShare apple/SatchelSafari apple/SatchelKit
swift test --package-path apple/SatchelKit --quiet
