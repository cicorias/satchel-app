# Sourced by scripts/run/*.sh. Resolves the target simulator and app identity.
#   SIM="iPhone 18 Pro Max"  device name (default)

sim="${SIM:-iPhone 18 Pro Max}"
bundle_id=$(node -p "require('./config/app.config.json').apple.bundleId")

# Newest runtime wins when several simulators share the name.
udid=$(xcrun simctl list devices available -j | node -e '
  const name = process.argv[1];
  const { devices } = JSON.parse(require("fs").readFileSync(0, "utf8"));
  for (const rt of Object.keys(devices).sort().reverse()) {
    const hit = devices[rt].find((d) => d.name === name);
    if (hit) { console.log(hit.udid); process.exit(0); }
  }
  process.exit(1);
' "$sim") || {
  echo "error: no available simulator named \"$sim\". Choose one of:" >&2
  xcrun simctl list devices available | grep -E '^\s+iPhone' | sed -E 's/ \(.*//' | sort -u >&2
  exit 1
}

# Quit whichever simulator UI app is running (Simulator.app before Xcode 27, DeviceHub after).
quit_sim_ui() {
  osascript -e 'tell application id "com.apple.iphonesimulator" to quit' 2>/dev/null || true
  osascript -e 'tell application id "com.apple.dt.Devices" to quit' 2>/dev/null || true
}
