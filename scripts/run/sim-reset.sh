#!/usr/bin/env bash
# Return the simulator to a factory-fresh state: uninstall Satchel, then erase ALL content and settings
# on that one simulator (other simulators are untouched).
#   SIM="iPhone 18 Pro Max"
#   PRUNE=1  also delete simulators whose runtime is no longer installed (`simctl delete unavailable`)
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/run/sim-lib.sh

xcrun simctl terminate "$udid" "$bundle_id" 2>/dev/null || true
xcrun simctl uninstall "$udid" "$bundle_id" 2>/dev/null || true
xcrun simctl shutdown "$udid" 2>/dev/null || true
xcrun simctl erase "$udid"
echo "erased $sim ($udid)"

if [ "${PRUNE:-0}" = "1" ]; then
  xcrun simctl delete unavailable
  echo "deleted simulators with unavailable runtimes"
fi
quit_sim_ui
