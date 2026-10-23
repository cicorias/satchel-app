# Enrichment of pending links

Status: resolved
Type: task
Blocked by: 06

§9.2.4 "Enrichment":
- **Loading:** for items with `metadataStatus: pending`, load the URL in a hidden, non-persistent `WKWebView` (no cookies from Safari), inject `capture.iife.js`, call `captureLink`, and merge the result. Set `complete`, or `failed` after N attempts.
- **Limits:** rate-limit requests per host, add timeouts, and skip enrichment on cellular when Low Data Mode is on.
- **When it runs:** on foreground and from background refresh. It must never block the UI.

**Done when** a link shared from another app shows its title, site, and image after the app enriches it (acceptance criterion). The scheduling and retry logic is unit-tested with a fake loader, and a fixture page served from a local file proves the injection path.

## Answer

**SatchelKit** (`Sources/SatchelKit/Enrichment/`)
- `Enricher` takes the store, a `LinkMetadataLoader`, `NetworkConditions`, a `Policy`, and an injectable clock and sleep. `run()` returns a `Report` (enriched, failed, retrying, skipped).
  - It loads pending items newest first, at most 20 per run, one at a time, at least 2 s apart per host, and 20 s each.
  - After a failure it waits 5 min, then 1 h; after the 3rd failure the item is `failed` (`Store.setMetadataStatus`, new, since the merge ranks `failed` below `pending`).
  - Attempt counts are kept in `syncState` under `enrichment/<id>`.
  - It does nothing when the network disallows it, and a second concurrent run returns at once.
- `Item.enriched(with:at:)` applies `LinkMetadata` (what `captureLink` returns).
  - Blank values never replace stored ones.
  - Identity (ID, URLs, canonical) never changes, so a canonical URL found later doesn't re-key the item.
  - Tags, the note, and `createdAt` are kept, and the status becomes `complete`. It saves through `Store.save`, so sync sends it.
- `WebMetadataLoader` fetches the HTML with one ephemeral `URLSession` request: no cookies, a Safari user agent, HTML only, at most 5 MB.
  - **Rendering:** it loads the HTML with `loadHTMLString` into a `WKWebView` with a non-persistent store, page JavaScript off, and a content rule blocking every subresource. It injects `capture.iife.js` in `.defaultClient` and calls `captureLink`.
  - **JSON-LD:** WebKit drops `<script>` elements when JavaScript is off, JSON-LD included, which lost the publisher and author. So `keepingJSONLD` carries those blocks as hidden `<textarea data-satchel-ld>`, and the injected script turns them back into inert JSON-LD scripts first.
- `NetworkPath` (NWPathMonitor): no enrichment while offline, or on cellular in Low Data Mode (`isConstrained`).

**App**
- `AppServices.syncAndEnrich()` runs after sync on foreground, from background refresh, and on pull to refresh, as a detached utility-priority task. `capture.iife.js` is now bundled with the app.
- Rows show the preview image (56 pt) and "details unavailable" for `failed`. A link's detail view shows the image above its description.
- **Remote images:** spec §11 says "Load remote images" is on by default in development builds, so Debug builds now register `loadRemoteImages = true`; Release still defaults to off until Phase 7. This corrects ticket 10, which defaulted to off. UI tests pass `-SatchelRemoteImagesOff`.

**Tests**
- `EnricherTests` (8), with `FakeLoader`, `FakeNetwork`, and `FakeClock`: filling in a link and keeping the user's tags, note, and identity; retry, then give up; success on a later attempt; spacing per host; a timeout; the batch limit; waiting for the network; leaving complete items alone.
- `WebMetadataLoaderTests`: the `news-og-twitter` fixture through the real loader matches `expected-metadata.json` exactly (JSON-LD author, publisher, and date included), plus the JSON-LD rewrite.
- Results: `mise run verify` passes 150 Swift tests (`verify:apple` now builds the capture bundle too); the UI suite passes 9/9.

**Device check (2026-10-23, iPhone 18 Pro Max, Debug build):**
- The Home Depot link shared from Notes got its product title, "The Home Depot", and an image.
- A new link from another app (microtrim.com) was filled in with its image showing in the row and the detail view.
- The old `example.org/satchel-test` link is retrying, as expected for an address that doesn't serve a normal page.
- All outbox entries are `sent`.
