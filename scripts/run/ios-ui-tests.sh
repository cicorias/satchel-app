#!/usr/bin/env bash
# Run the UI tests (they drive Settings and Safari) on a simulator.
#   SIM="iPhone 18 Pro Max"     device name (default)
#   ONLY="SafariExtensionUITests/testA_EnableSafariExtension"  run one test or class (optional)
#   VERBOSE=1  stream full xcodebuild output, including XCTest's step-by-step activity log
# Log: apple/build/ui-tests.log. Screenshots: the newest apple/build/DerivedData/Logs/Test/*.xcresult.
#
# Xcode 27.1 sometimes never exits after the tests finish (it stalls finalizing the result bundle,
# logging "operatingSystemBuild … invalidDigitCount"), sometimes before printing "** TEST …**". So
# xcodebuild runs in the background; once the top-level "Test Suite 'All tests'/'Selected tests'
# passed|failed" line appears it gets a grace period, then is stopped.
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/run/sim-lib.sh

xcrun simctl boot "${udid}" 2>/dev/null || true
xcrun simctl bootstatus "${udid}" -b >/dev/null
scripts/build/xcodegen.sh
log=apple/build/ui-tests.log
mkdir -p apple/build
: >"${log}"

common=(-project apple/Satchel.xcodeproj -scheme Satchel -destination "id=${udid}"
  -derivedDataPath apple/build/DerivedData
  # Ad-hoc signing embeds the entitlements, so the app and its extensions share the App Group store.
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
quiet=(-quiet)
if [ "${VERBOSE:-0}" = "1" ]; then quiet=(); fi

# Build, then install the fresh app explicitly: `xcodebuild test` doesn't reliably (re)install the
# host app of a UI-test target, which leaves Safari running stale extension files.
# The first test re-enables the Safari extension after the reinstall.
xcodebuild build-for-testing "${common[@]}" ${quiet[@]+"${quiet[@]}"}
xcrun simctl uninstall "${udid}" "${bundle_id}" 2>/dev/null || true
xcrun simctl install "${udid}" apple/build/DerivedData/Build/Products/Debug-iphonesimulator/Satchel.app

# A hung UI interaction fails the test after 3 minutes instead of blocking forever.
args=(test-without-building "${common[@]}"
  -test-timeouts-enabled YES -default-test-execution-time-allowance 180 -maximum-test-execution-time-allowance 300)
if [ -n "${ONLY:-}" ]; then args+=(-only-testing:"SatchelUITests/${ONLY}"); fi

xcodebuild "${args[@]}" >"${log}" 2>&1 &
xcb=$!
trap 'kill "${xcb}" 2>/dev/null || true' EXIT

# Echo new log lines as they arrive (filtered unless VERBOSE=1). A polling loop rather than
# `tail -f | grep &`, which leaves an orphaned tail holding stdout open after the script exits.
shown=0
show_new_lines() {
  local total
  total=$(wc -l <"${log}" | tr -d ' ')
  if [ "${total}" -gt "${shown}" ]; then
    if [ "${VERBOSE:-0}" = "1" ]; then
      sed -n "$((shown + 1)),${total}p" "${log}"
    else
      sed -n "$((shown + 1)),${total}p" "${log}" |
        grep -E "Test Case .*(passed|failed)|error:|\*\* TEST|Test Suite '(All|Selected) tests' (passed|failed)|SPIKE-RESULT" || true
    fi
    shown=${total}
  fi
}

marker=""
while kill -0 "${xcb}" 2>/dev/null; do
  show_new_lines
  marker=$(grep -oE "Test Suite '(All tests|Selected tests)' (passed|failed)|\*\* TEST (SUCCEEDED|FAILED) \*\*" "${log}" | tail -1 || true)
  [ -n "${marker}" ] && break
  sleep 2
done
# Tests finished (or xcodebuild exited): allow a grace period, then stop a stalled xcodebuild.
for _ in $(seq 1 15); do kill -0 "${xcb}" 2>/dev/null || break; sleep 2; done
if kill -0 "${xcb}" 2>/dev/null; then
  echo "note: xcodebuild didn't exit after the tests finished; stopping it (Xcode 27.1 result-bundle stall)"
  kill "${xcb}" 2>/dev/null || true
fi
xcb_status=0
wait "${xcb}" 2>/dev/null || xcb_status=$?
show_new_lines

marker=$(grep -oE "Test Suite '(All tests|Selected tests)' (passed|failed)|\*\* TEST (SUCCEEDED|FAILED) \*\*" "${log}" | tail -1 || true)
case "${marker}" in
  *SUCCEEDED* | *passed) status=0 ;;
  "") status=$((xcb_status == 0 ? 1 : xcb_status)) ;; # no result at all: build or launch failure
  *) status=1 ;;
esac
echo "log: ${log}"
exit "${status}"
