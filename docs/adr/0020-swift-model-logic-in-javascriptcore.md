# ADR-0020: Swift runs the TypeScript model in JavaScriptCore

- **Status:** Accepted
- **Date:** 2026-10-22

**Context.** The Apple targets need the exact URL normalization (§7.2), item IDs, and merge rules (§7.3) that `packages/model` implements. If the two disagree, the same page saved from Chrome and from the iPhone becomes two items, and sync merges differently on each side. A Share Extension invoked from a non-Safari app has only a URL, so it must compute the ID natively.

**Decision.** SatchelKit calls `@satchel/model` through JavaScriptCore instead of porting it.
- A dedicated bundle, `packages/model/dist/model.jsc.iife.js`, exposes `globalThis.SatchelModel`.
- Bare JavaScriptCore has no `URL`, `URLSearchParams`, or `TextEncoder` (checked on macOS 27 and iOS 27), so that bundle adds core-js's `URL`/`URLSearchParams` polyfill and a 20-line UTF-8 `TextEncoder` (`src/jsc/`).
- The browser bundle (`model.iife.js`) and the workspace ESM keep using the native APIs.

**Measurements** (2026-10-22, Phase 3 ticket 01):

| | Mac (swiftc -O) | iPhone 18 Pro Max, 3 cold launches |
|---|---|---|
| JSContext + evaluate the 190 KB bundle | 11 ms | 10–23 ms |
| First `normalizedUrlFor` + `itemIdFor` | 1.4 ms | 1.6–4.8 ms |
| Later calls | — | 0.27 ms |
| Memory (phys_footprint, context + 1,000 calls) | — | +8 MB (2.2 → 10.2 MB) |

- **Parity:** on 118 inputs, the JSC bundle in real JavaScriptCore and the native-URL bundle in Node produced identical normalized URLs and IDs. The inputs were every URL in the model tests and fixtures, plus IDNs, IPv6, dot segments, backslashes, embedded tabs and newlines, userinfo, trailing-dot hosts, malformed percent-escapes, and cross-site canonicals.
- **CI:** `packages/model/test/jsc-bundle.test.ts` re-checks this on every run. It runs the JSC bundle in a global with no `URL` or `TextEncoder` and compares it with the native one.

**Reasons.**
- One implementation can't drift, and drift here means duplicate items: silent, data-shaped bugs that are hard to repair after sync.
- The Public Suffix List stays in one place (tldts), updated by one dependency bump.
- The costs are small next to a Share Extension's memory budget and the 1-second link-save target (§3.2).

**Consequences.**
- ✅ Swift wraps three calls (`normalizedUrlFor`, `itemIdFor`, `mergeItems`) and passes JSON across the bridge.
- ⚠️ Each process that needs the model holds a JSContext. Create it lazily and reuse it, and keep it off the main thread when the UI is busy.
- ⚠️ The polyfill could, in principle, disagree with a browser's native `URL` on an input the parity set doesn't cover. When a mismatch is found, add it to `test/url-inputs.json`.
- ⚠️ New runtime dependency: `core-js@3.51.0`, bundled only into `model.jsc.iife.js`. Its install script is denied in `pnpm-workspace.yaml`, since it only prints a funding notice.

**Alternatives considered.**
- *Port to Swift with shared vectors:* two implementations, and a Swift Public Suffix List with its own update process. Foundation's `URL` is RFC 3986, not WHATWG, so the port would need its own parser to match browsers.
- *A hidden WKWebView for native WebKit `URL`:* it's asynchronous, starts a WebContent process, and is too slow and heavy for the Share Extension's synchronous save.
- *Hybrid (JSC for IDs, Swift for merge):* possible later if merge calls during sync prove hot. Measure first.
