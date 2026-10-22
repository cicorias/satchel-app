# SatchelKit: normalization, IDs, and merge rules

Status: resolved
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

## Answer

**`SatchelModel`** (`apple/SatchelKit/Sources/SatchelKit/SatchelModel.swift`) runs `model.jsc.iife.js` in one lazily created `JSContext` held in a `Mutex`, so the type is `Sendable`. Its API:
- `normalizedURL(pageURL:canonicalURL:)`
- `itemID(forNormalizedURL:)`
- `merge(_:_:) -> MergeResult` (`item`, `body: .a/.b/.none`, `replacesBody`)
- `bundled(in:)`

How it works:
- **Items cross the bridge as JSON text** through a small `__mergeJSON` shim, so the result never depends on how `JSValue` converts objects.
- **Errors:** JavaScript exceptions become `SatchelModelError.unsupportedURL` (for `UnsupportedUrlError`) or `.script(message)`. A missing resource is `.missingScript`.
- **Bundling:** `model.jsc.iife.js` is now a resource of `Satchel`, `SatchelShare`, and `SatchelSafari` (`apple/project.yml`, from `Staged/web/`), and the simulator build contains it in all three.
- **Build order:** `scripts/verify/apple.sh` builds `@satchel/model` before `swift test`.

**Shared vectors** in `fixtures/model/vectors/`:
- `normalization.json` (118 cases, including the error cases) and `merge.json` (5 pairs, with results).
- `packages/model/test/vectors.test.ts` writes them (`UPDATE_VECTORS=1`) and checks them on every run.
- `SatchelModelTests` checks that the bridge returns exactly those values, that merge is commutative, that every contract fixture derives its own `normalizedUrl` and `id`, that errors are typed, and that 64 concurrent calls are safe.
