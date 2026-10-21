#!/usr/bin/env bash
# Stop Satchel, shut the simulator down, and quit the simulator UI. Keeps the installed app and its data.
#   SIM="iPhone 18 Pro Max"  ALL=1 shuts down every booted simulator instead
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/run/sim-lib.sh

if [ "${ALL:-0}" = "1" ]; then
  xcrun simctl shutdown all
  echo "shut down all simulators"
else
  xcrun simctl terminate "$udid" "$bundle_id" 2>/dev/null || true
  xcrun simctl shutdown "$udid" 2>/dev/null || true
  echo "shut down $sim"
fi
quit_sim_ui
