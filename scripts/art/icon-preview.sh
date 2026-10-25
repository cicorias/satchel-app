#!/usr/bin/env bash
# Render the Liquid Glass app icon (apple/Satchel/Resources/AppIcon.icon) the way iOS draws it, with Icon Composer's
# ictool, into apple/build/icon-preview/: default, dark, and tinted. Run `mise run art` first after a design change.
set -euo pipefail
cd "$(dirname "$0")/../.."

tools="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables"
if [ ! -x "${tools}/ictool" ]; then
  echo "error: ictool not found in ${tools}; it ships with Xcode 26 or later" >&2
  exit 1
fi
out=apple/build/icon-preview
mkdir -p "${out}"
render() {
  "${tools}/ictool" apple/Satchel/Resources/AppIcon.icon --export-image --output-file "${out}/$1.png" \
    --platform iOS --rendition "$2" --width 1024 --height 1024 --scale 1 "${@:3}" >/dev/null
  echo "  ${out}/$1.png"
}
render default Default
render dark Dark
render tinted TintedDark --tint-color 0.6 --tint-strength 0.75
