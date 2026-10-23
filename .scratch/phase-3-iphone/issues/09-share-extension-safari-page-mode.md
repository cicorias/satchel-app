# Share Extension from Safari: page mode, tags, and note

Status: resolved
Type: task
Blocked by: 06

§9.2.2:
- **Preprocessing script:** add `NSExtensionJavaScriptPreprocessingFile` to `SatchelShare`, which `project.yml` notes as a Phase 3 item. The script wraps `capture.iife.js` and returns `captureLink` and `capturePage` results (FR-4).
- **Sheet:** "Save link" (primary), "Save page" (only when a page capture came back), tags with autocomplete from `Store`, and a note.
- **Memory:** never load images. Pass Markdown as a string, and measure peak memory on the device with a large page, since share extensions have tight limits.
- **Re-saves:** follow FR-6 (link → page upgrades; page → page asks before replacing).

**Done when** sharing from Safari on the iPhone saves both a link and a page (acceptance criterion). A non-Safari share still takes ticket 06's link path. A UI test covers the sheet on the simulator.

## Answer

**Preprocessing**
- `apple/SatchelShare/preprocessing.js` sets `ExtensionPreprocessingJS`. In the shared page, `run` calls `captureLink` and `capturePage`, builds both items with `itemFromCapture` (client `ios-share`, the capture engine's `version`), and completes with `{ satchel: JSON }`. The completion is asynchronous, after `capturePage` resolves, and Safari accepts that.
- `scripts/build/web-for-apple.sh` stages it as `Staged/web/SatchelSharePreprocessing.js` (capture IIFE + wrapper). `project.yml` adds it to `SatchelShare` and sets `NSExtensionJavaScriptPreprocessingFile`.
- Biome doesn't lint this file, because it ignores `apple/` and won't re-include a single file under it.

**SatchelKit**
- `SafariShareCapture` decodes the result: `url`, `title`, the `link` and `page` items (each with an optional `body`), and `linkError`/`pageError`.
- `TagInput` handles typed tags: it splits on commas or periods (the user's choice, also applied to the popup), plus `fragment`, `completing`, and `suggestions`.
- `Item.adding(tags:note:)` merges in the typed tags and note.
- `ItemSaver.saveCapture(_:body:existingPage:)` and `problem(with:body:)` now hold the FR-6 and validation rules for both extensions: ID and URL consistency, a body exactly for pages, the 10 MB cap, ask/keep/replace. `ExtensionMessageHandler` calls them.

**Sheet** (`ShareViewController.swift`)
- **From Safari:** Save link (the captured link item, with full metadata) and Save page (only when a page capture came back; otherwise it shows why).
- **From other apps:** Save link through ticket 06's `saveLink`.
- **Fields:** tags with suggestion buttons from `Store.tags` and a note, in both cases.
- **Saved page:** a page over a saved page shows "This page is already saved. Replace saved copy?" with Replace, Keep saved copy, or Cancel.
- **Memory report:** Debug builds append the footprint to `<App Group>/Library/share-memory.jsonl` (`MemoryReport.swift`).

**Tests**
- `TagInputTests` (3) and `SafariShareCaptureTests` (3). SatchelKit has 139 tests.
- `ShareExtensionUITests.testSharingAPageFromSafariWithTags`: shares a page from Safari, types tags, and taps Save page. It then shares again, gets the replace prompt, and taps Keep saved copy, and the row is a page.
- The UI suite passes 5/5.

**Device check (2026-10-23, iPhone 18 Pro Max, Debug build)**
- **Pages from Safari:** saved with tags split on periods (`cooking. pizza` → `["cooking","pizza"]`). The replace prompt worked (Keep, then Replace).
- **Same page with different tracking parameters:** shared twice, still one item.
- **Large page:** "History of the United States" (26,687 words, 336 KB of Markdown, stored inline because it's under 512 KB) saved quickly.
- **Memory:** the peak footprint was 29.2 MB with 204 MB still available. Small pages peaked at 13–27 MB.
- **Other apps:** a link shared from Notes offered only Save link and was saved as `pending`.
- **Sync:** every outbox entry was `sent` after 1 attempt.
