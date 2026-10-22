# SatchelKit: normalization, IDs, and merge rules

Status: ready-for-agent
Type: task
Blocked by: 01, 02

Per ADR-0020, wrap `model.jsc.iife.js` in SatchelKit instead of porting:

- **`SatchelModel`:** a `Sendable` type holding a lazily created `JSContext` behind a `Mutex`. It exposes:
  - `normalizedURL(pageURL:canonicalURL:) throws -> String`
  - `itemID(for:) throws -> String`
  - `merge(_:_:) throws -> MergeResult` (`item`, `body`, `replacesBody`)

  JSON crosses the bridge using ticket 02's Codable `Item`.
- **Errors:** JS exceptions map to typed Swift errors (`UnsupportedURL`, `script(message)`).
- **Bundling:** `scripts/build/web-for-apple.sh` already stages `model.jsc.iife.js` in `apple/Staged/web/`. Bundle it into the app and both extensions (`project.yml` resources). SatchelKit takes the script source at init, so `swift test` can read `packages/model/dist/model.jsc.iife.js` instead. `verify:apple` must build `@satchel/model` first.
- **Shared vectors:** export them from the TypeScript tests to `fixtures/model/` (normalization inputs and outputs from `packages/model/test/url-inputs.json`, IDs, and merge pairs with results). The Swift tests check that the bridge returns them unchanged.

**Done when** Swift passes every shared vector, the TypeScript tests also run against the exported vectors, and the commutativity property holds on the Swift side.
