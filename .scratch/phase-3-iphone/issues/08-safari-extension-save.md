# Safari extension: save links and pages from the popup through the native handler

Status: resolved
Type: task
Blocked by: 06

ADR-0007 and §9.1, Safari part only. Chrome and Edge get their platform adapter in Phase 2.

- **Popup UI** (`apps/extension/src/entrypoints/popup`), shared with Chrome and Edge later:
  - "Save link" (primary) and "Save page", optional tags with autocomplete, and a note (FR-5).
  - Confirmation, plus "Replace saved copy?" when the native side reports `replacesBody` (FR-6).
  - Send `ping` when the popup opens (ADR-0007 addendum).
- **Capture:** inject `packages/capture` into the active tab on the user's action (`activeTab` + `scripting`, §11), and run `captureLink`/`capturePage` there.
- **Platform adapter** (`apps/extension/src/platform/`): `saveItem`, `status`, and `tags`, implemented for Safari with `browser.runtime.sendNativeMessage`. Nothing else may call `browser.*` (AGENTS.md).
- **`SafariWebExtensionHandler`:** handle `save` (validate, enforce the 10 MB cap with a clear error, `Store.save`, then `OneShotSaver`), `status`, and `tags`. Keep `ping`.

**Done when**:
- `mise run test:ios-ui` gains a test that saves a link and a page from the Safari popup on the simulator, and the item appears in the library with its body.
- The handler's message handling is unit-tested in SatchelKit (move the logic out of the extension target).

## Answer

**Decision (asked 2026-10-23):** a page's stored body is `bodyMarkdown`, without frontmatter. Frontmatter is generated from the Item on export, so it never goes stale. This is recorded in spec §5.

**TypeScript**
- `packages/capture/src/item.ts`: `itemFromCapture(capture, { pageUrl, client, version, tags, note, selection, now })` returns `{ item, body }`, plus `normalizeTags`.
  - The ID comes from `normalizedUrlFor(pageUrl, canonicalUrl)`.
  - Blank metadata is omitted.
  - A page gets `capturedAt`, `page` (stats, `extractor + converter`, images), and `body = bodyMarkdown`.
  - The IIFE exposes both functions, so ticket 09's preprocessing script can use them.
- `apps/extension`:
  - `entrypoints/capture.ts` is an unlisted script, built as `/capture.js`, that sets `globalThis.SatchelCapture`.
  - `platform/tab.ts`'s `captureTab` injects it on the user's action (`activeTab` + `scripting`), then runs capture and `itemFromCapture` in the page. The popup chunk stays at 5 KB, and the engine (622 KB) loads only into the page.
  - `platform/types.ts` defines the `PlatformAdapter`: `client`, `warmUp`, `save(captured, existingPage)`, `tags`, `status`.
  - `platform/safari.ts` implements it with `sendNativeMessage`. `platform/index.ts` picks the adapter; Chrome and Edge get a Phase 2 stub.
  - **Popup:**
    - title and URL;
    - tags (comma-separated, autocompleting the tag being typed from `tags`) and a note;
    - Save link (Enter) and Save page;
    - "Replace saved copy?" with Replace or Keep saved copy;
    - a status line (saved, saved but not synced yet, or the error);
    - `ping` on open, and "This page/link is saved" from `status`.

**Native**
- `SatchelKit/ExtensionMessageHandler` handles `ping`, `save`, `tags` and `status` as JSON objects in and out.
  - **Validation:** `save` re-derives the normalized URL and ID through `SatchelModel` and rejects a mismatch. A page needs a body and a link can't have one. Bodies over 10 MB are rejected (`too-large`, "Save it as a link instead").
  - **Saved page:** over a saved page, `existingPage: ask` replies `confirm: "replace"` without saving. `keep` saves the new tags, note and metadata but keeps the stored body and its `page`/`capturedAt`. `replace` saves everything.
  - **Saving:** goes through `ItemSaver` (outbox, then `OneShotSaver`). The reply has `synced` and `syncError`.
- `ItemSaver.save` now sends CloudKit the body the merge kept, not just the incoming one.
- `SafariWebExtensionHandler` keeps one handler per process and answers in a task, with `Store.resume()`/`suspend()` around each message.
- The library row shows "page, N min" for pages.

**Tests**
- `itemFromCapture`: 5 Vitest tests. The IIFE API list is updated.
- `ExtensionMessageHandlerTests` (10): ping, a link from JSON, a page with its body (also in the CloudKit record), the link → page upgrade without asking, ask/keep/replace for a saved page, the 10 MB cap, inconsistent items, a queued save, tags and status, unknown types.
- `SafariExtensionUITests.testC_SavesALinkThenAPageFromThePopup`:
  - opens a new URL, adds a tag, and taps Save link, waiting for "Link saved";
  - taps Save page, waiting for "Page saved";
  - finds the row by its computed ID in the app, marked as a page. The handler only stores a page that has a body.
- Results: `mise run verify` passes (133 Swift tests); the UI suite passes 4/4.

**Also:** `.gitleaks.toml` now skips SwiftPM `.build/` directories. GRDB's checkout vendors SQLite test keys, which the working-tree scan flagged.

**Device check (2026-10-23, iPhone 18 Pro Max, Debug build):**
- **Popup saves:** a link save, then a page save, then a re-save with Keep and then Replace, all of one article. The result is one page item from `safari-ios`, with its `createdAt` kept from the link save and a 1,668-character body that starts at `# title` with no frontmatter. Its outbox entry was `sent` after 1 attempt, about 0.5 s after the last save.
- **Tags:** `great tools` became a single tag. The user then chose to split tags on commas or periods (ticket 09).
- **Open question:** the body shows one image twice in a row. It could be a lazy-load duplicate or the page itself, and a capture fix would need a fixture.
