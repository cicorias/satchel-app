# IIFE bundles and timing report

Status: resolved
Type: task
Blocked by: 06, 08

Confirm that `capture.iife.js` and `render.iife.js` expose their full APIs and load in a plain `<script>` context (a linkedom or happy-dom smoke test). Add informational timing over the fixture set to CI output (spec §14 Phase 1 criteria).

## Answer

**Smoke tests:**
- `packages/capture/test/iife.test.ts` runs `dist/capture.iife.js` in a fresh `node:vm` global that has only linkedom's `window`, `document`, and `DOMParser`. It checks the full `SatchelCapture` API, then runs `captureLink` and `capturePage` through it.
- `packages/render/test/iife.test.ts` evaluates `dist/render.iife.js` inside a jsdom window and checks the `SatchelRender` API, including sanitizing.
- Turbo's `test` now depends on the package's own `build`, so the bundles exist before the tests run.

**Timing:**
- `mise run report:capture-timing` (`scripts/verify/capture-timing.sh`, `test/timing.test.ts`) prints the median of 5 runs per fixture after a warm-up. It never fails, and pages over budget are marked `!`.
- It's a separate step in `ci-web.yml`, so the table shows in the CI log. Turbo hides test output.
- Locally, on the 25 fixtures, `captureLink` takes well under 1 ms and `capturePage` a few to a few tens of ms, against budgets of 50 ms and 1.5 s.

**Bundle sizes** (minified):
- `capture.iife.js` is about 495 KB, 160 KB gzipped: Defuddle 323 KB, tldts (Public Suffix List) 122 KB, our code 24 KB, Turndown 11 KB.
- `render.iife.js` is 143 KB, 57 KB gzipped.

tldts is the obvious target if size matters. `tldts-experimental` is smaller and still supports private domains. Weigh it in Phase 3, when the Share Extension's memory limits are known.
