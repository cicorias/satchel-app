# Decide how Swift gets URL normalization, IDs, and merge rules

Status: resolved
Type: research
Blocked by: -

Swift needs the exact §7.2 normalization, `itemIdFor`, and §7.3 `mergeItems` that `packages/model` implements.
- A Share Extension invoked from a non-Safari app has only a URL, and it must compute the same ID that Chrome would.
- Sync merges conflicting records.
- A mismatch between the two languages would silently create duplicate items.

Options:

- **(a) Port to Swift**, with shared test vectors exported from the TypeScript tests (`fixtures/model/url-vectors.json`, `merge-vectors.json`). It needs the Public Suffix List in Swift: a bundled data file with its own update process, or a Swift PSL package. Two implementations have to be kept in step by tests.
- **(b) Run `@satchel/model` in JavaScriptCore.** Build a `model.iife.js` (tldts plus @noble/hashes, about 135 KB minified) and call it from a small Swift wrapper in SatchelKit. It is one implementation, identical by construction. The costs: a JSContext in each process, and checking its cold-start time and memory in the Share Extension (§9.2.2 memory limits).
- **(c) A hybrid:** (b) for normalization and IDs, where a mismatch corrupts identity, and (a) for merge rules, which are simple and often called during sync.

Measure (b) in the Share Extension on a device: JSContext creation plus the first `normalizedUrlFor` call, and peak memory. Then recommend one option.

**Done when** an ADR (0020) records the decision and the measurements, and tickets 03 and 07 are updated to match.

Agent's starting recommendation: (b), unless the measurements rule it out. One implementation removes a whole class of duplicate-item bugs, and the capture engine already ships as an IIFE the same way.

## Answer

Resolved on 2026-10-22. The user chose (b), and the measurements support it.

**ADR-0020: Swift runs `@satchel/model` in JavaScriptCore.**
- **Missing Web APIs:** bare JSC has no `URL` or `TextEncoder`, so a dedicated `model.jsc.iife.js` (190 KB) adds core-js's `URL` polyfill and a small UTF-8 encoder.
- **On the iPhone:** 10–23 ms to create the context and load the bundle, 1.6–4.8 ms for the first call, 0.27 ms per later call, and about +8 MB of memory.
- **Parity:** the results matched native `URL` on all 118 parity inputs, and `test/jsc-bundle.test.ts` keeps checking that in CI.
- **Probe:** a reference copy is in `../research/01-jsc-probe.md`.

Tickets 03 and 07 are updated to match.
