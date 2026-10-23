#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
# Build the model/capture/render IIFEs and the WXT Safari (MV3) target, then stage them where Xcode expects (spec §12.3).
pnpm turbo run build --filter=@satchel/model --filter=@satchel/capture --filter=@satchel/render --output-logs=errors-only
pnpm --filter @satchel/extension build:safari >/dev/null

stage=apple/Staged
rm -rf "$stage/safari-extension" "$stage/web"
mkdir -p "$stage/web"
cp packages/model/dist/model.jsc.iife.js packages/capture/dist/capture.iife.js packages/render/dist/render.iife.js "$stage/web/"
# The Share Extension's preprocessing file (NSExtensionJavaScriptPreprocessingFile): the capture engine plus the
# wrapper Safari calls.
cat packages/capture/dist/capture.iife.js apple/SatchelShare/preprocessing.js >"$stage/web/SatchelSharePreprocessing.js"
cp -R apps/extension/.output/safari-mv3 "$stage/safari-extension"
echo "staged web assets in $stage/"
