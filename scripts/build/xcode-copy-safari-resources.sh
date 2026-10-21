#!/usr/bin/env bash
# Xcode build phase (SatchelSafari): copy the staged WXT Safari build to the root of the .appex,
# where the packager puts it (ADR-0005 addendum). Entries copied by the previous build are removed
# first, using a manifest kept in the target's intermediates, so renamed chunks don't pile up in
# the bundle. A plain `rsync --delete` would also wipe the appex's binary and Info.plist.
set -euo pipefail

src="${SRCROOT:?run from an Xcode build phase}/Staged/safari-extension"
dest="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}"
manifest="${DERIVED_FILE_DIR:?}/safari-web-resources.txt"

if [ ! -f "${src}/manifest.json" ]; then
  echo "error: ${src}/manifest.json missing; the WebAssets phase should have staged the Safari build" >&2
  exit 1
fi

if [ -f "${manifest}" ]; then
  while IFS= read -r entry; do
    [ -n "${entry}" ] && rm -rf "${dest:?}/${entry}"
  done <"${manifest}"
fi

mkdir -p "$(dirname "${manifest}")"
: >"${manifest}"
for path in "${src}"/* "${src}"/.[!.]*; do
  [ -e "${path}" ] || continue
  entry=$(basename "${path}")
  cp -R "${path}" "${dest}/"
  echo "${entry}" >>"${manifest}"
done
