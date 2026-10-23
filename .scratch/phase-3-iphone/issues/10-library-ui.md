# Library: search, filters, detail view, export, delete

Status: resolved
Type: task
Blocked by: 06

FR-7 and §9.2.4 "Library UI":
- **List and search:** search with FTS5 from ticket 04, filters by tag and kind, newest first.
- **Detail view:** renders the Markdown with `render.iife.js` in a `WKWebView`. Remote images follow the setting from ticket 12. No navigation inside the web view: links open in Safari.
- **Actions:** copy Markdown, export `.md` through the share sheet (link Items export frontmatter plus the description, §5), delete, and open the original URL.
- **Pending state:** show it (FR-8).

**Done when** UI tests on the simulator cover search, opening the detail view, export, and delete. The detail view is verified to run no page scripts and to load no remote content while remote images are off.

## Answer

**List** (`LibraryView`, `LibraryModel`)
- **Search:** `.searchable` runs the store's FTS5 search over title, description, site, tags, and body, sorted by relevance. Without a search the list is newest first (`recentlyCreated`).
- **Filters:** a menu for kind (All, Pages, Links) and tag (from `Store.observeTags()`, new). Changing the query restarts the items observation (`.task(id:)`).
- **Rows:** each row links to the detail view. Swipe to delete, pull to sync, outbox badges (FR-8). "No results" shows when a search or filter matches nothing.

**Detail** (`ItemDetailView`, `MarkdownWebView`)
- **Pages** render their body with `render.iife.js` in a `WKWebView`. The header (title, byline, tags, note) is built from text nodes.
  - Content JavaScript is off. The renderer runs in the `.defaultClient` content world and its HTML is sanitized by DOMPurify.
  - The CSP is `default-src 'none'; style-src 'unsafe-inline'; img-src data:`, which adds `https: http:` only when remote images are on.
  - A non-persistent data store is used, and data detectors are off.
  - Links open in Safari; only `about:` (the shell and footnote jumps) navigates.
- **Images:** remote images follow `loadRemoteImages` in the App Group defaults, which is off by default (ticket 12 adds the toggle). The ⋯ menu offers "Load Images (N)" for the item being viewed.
- **Links** show their description natively.
- **Actions:**
  - **Export:** `ShareLink` with `<title>.md`, written to a temporary `Export/` folder.
  - **⋯ menu:** Open in Safari, Copy Markdown (the same text as the export), and Delete, with a confirmation that pops back to the list.
  - **Banner:** the outbox state shows in a bottom banner.

**Export format:** `formatFrontmatter` moved from `@satchel/capture` to `@satchel/model`, and capture re-exports it.
- `frontmatterFor(item)` and `markdownFile(item, body?)` add the export: frontmatter from the item's current fields, then the body, or for a link `# title` plus the description (spec §5).
- Swift calls it as `SatchelModel.markdownFile(for:body:)` through the JSC bridge.

**Tests**
- **Model:** `frontmatter.test.ts` (3) and `SatchelModelTests.exportsMarkdownFiles`.
- **UI:** `LibraryUITests` (4) run on items seeded with `-SatchelSeedLibrary` (Debug only, `UITestSeed`).
  - Search finds by title, and by body text ("footnote").
  - The Links filter hides pages.
  - The detail view's Debug-only `render-report` reads `scripts 0, handlers 0, resources 0, violations 0, blocked 2` for a body that tries an inline `<script>`, an `onerror` handler, and two remote images.
  - Export opens the share sheet naming the file.
  - Swipe-delete removes the row.
- **Results:** the UI suite passes 9/9 (row lookups now use `firstMatch`, since a navigation link and its contents share the identifier). `mise run verify` passes 140 Swift tests.

**Device check (2026-10-23, iPhone 18 Pro Max):** the user checked search (by title, tag, and body text), the kind and tag filters, the rendered detail view (placeholders, then Load Images, links opening in Safari, footnote jumps, a long Wikipedia page), Export to Files with the frontmatter, Copy Markdown, Open in Safari, the link detail view, and delete. All passed.
