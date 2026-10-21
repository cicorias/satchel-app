#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
# Scan git history and the working tree for secrets (ADR-0014).
gitleaks git --redact --no-banner .
gitleaks dir --redact --no-banner .
