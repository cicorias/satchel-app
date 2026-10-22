#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
# Lint Swift with swift-format, then run SatchelKit tests on the host.
swift format lint --strict --recursive --configuration .swift-format apple/Satchel apple/SatchelShare apple/SatchelSafari apple/SatchelUITests apple/SatchelKit
# SatchelKit's tests run the JavaScriptCore model bundle (ADR-0020), so build it first.
pnpm turbo run build --filter=@satchel/model --output-logs=errors-only
swift test --package-path apple/SatchelKit --quiet
