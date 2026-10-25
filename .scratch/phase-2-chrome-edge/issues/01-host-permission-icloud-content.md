# Host permission for CloudKit asset upload and download

Status: ready-for-agent
Type: task
Blocked by: -

**Do this first when you pick Phase 2 up.** It's small and doesn't need CloudKit Console access.

## Problem

CloudKit Web Services hands out asset URLs on a different host from the API:
- `assets/upload` returns an upload URL on `*.icloud-content.com`, which the client POSTs the bytes to.
- Asset fields (`bodyAsset`, and `ImageAsset.file` in Phase 5) come back with a `downloadURL` on the same host family.

`apps/extension/wxt.config.ts` and `docs/spec.md` §9.1.2 grant only `https://api.apple-cloudkit.com/*`. Any body over 512 KB (stored as `bodyAsset`, spec §8.2) would fail to upload or load in Chrome and Edge.

## Work

- Add `https://*.icloud-content.com/*` to `host_permissions` for chrome and edge only in `apps/extension/wxt.config.ts`. Safari gets none (ADR-0007).
- Add a row to the permissions table in `docs/spec.md` §9.1.2: "host `https://*.icloud-content.com/*` | CloudKit asset upload and download (`assets/upload`, asset `downloadURL`) | chrome, edge".
- If the extension has a manifest test, assert both hosts for chromium and none for safari. If it doesn't, check the built `.output/chrome-mv3/manifest.json` and `.output/safari-mv3/manifest.json` by hand and say so in the Answer.
- `mise run verify:web` and `mise run build:extension chrome` pass.

**Follow-up for Spike A (02):** confirm the exact asset host from a real `assets/upload` response. If it differs (for example `cvws.icloud-content.com` only, or another domain), narrow or fix the pattern there.

**Store review note:** a new host permission on an already-published extension shows a permission warning on update. Nothing is published yet, so adding it now costs nothing. That's the reason to do it before the first Chrome/Edge release.
