#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
# Manage the CloudKit schema from apple/CloudKit/Satchel.ckdb with Xcode's cktool (ADR-0004 addendum).
#   scripts/deploy/cloudkit-schema.sh validate   check the file against the container (default)
#   scripts/deploy/cloudkit-schema.sh import     validate, then replace the Development schema
#   scripts/deploy/cloudkit-schema.sh export     write the live schema to apple/build/ for diffing
# ENV=production works for validate and export. Production is deployed from CloudKit Console.
# One-time: `xcrun cktool save-token --type management` (stored in the keychain, never in the repo).
action="${1:-validate}"
env="${ENV:-development}"
schema=apple/CloudKit/Satchel.ckdb

if [ ! -f config/local.config.json ]; then
  echo "error: config/local.config.json is missing; run 'mise run setup:config' (docs/setup/apple.md)" >&2
  exit 1
fi
team=$(node -p "require('./config/local.config.json').apple?.developmentTeam ?? ''")
container=$(node -p "require('./config/app.config.json').apple.iCloudContainer")
if [ -z "$team" ]; then
  echo "error: no apple.developmentTeam in config/local.config.json" >&2
  exit 1
fi

case "$env" in
  development|production) ;;
  *) echo "error: ENV must be development or production" >&2; exit 2 ;;
esac

target=(--team-id "$team" --container-id "$container" --environment "$env")
case "$action" in
  validate)
    xcrun cktool validate-schema "${target[@]}" --file "$schema"
    echo "valid against $container ($env)"
    ;;
  import)
    if [ "$env" != development ]; then
      echo "error: import only targets Development; deploy to Production from CloudKit Console" >&2
      exit 2
    fi
    xcrun cktool import-schema "${target[@]}" --validate --file "$schema"
    echo "imported $schema into $container ($env)"
    ;;
  export)
    mkdir -p apple/build
    out="apple/build/cloudkit-schema.$env.ckdb"
    xcrun cktool export-schema "${target[@]}" --output-file "$out"
    echo "exported to $out (compare: diff -u $schema $out)"
    ;;
  *)
    echo "usage: $0 [validate|import|export]" >&2
    exit 2
    ;;
esac
