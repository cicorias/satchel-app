# Full-page library manager in the web extension

Status: needs-triage
Type: prototype
Blocked by: 02

A full-tab page in the extension for viewing and editing your saves, built around tags, in the spirit of Chrome's Bookmark Manager and Edge's Favorites. It builds on the library page in spec §9.1.1 and §9.1.4. Expanded from idea 3 on 2026-10-25.

## Decisions so far

- **Browsers:** Chrome, Edge, and Safari on macOS. Not Safari on iOS or iPadOS, where the app is the library.
- **Layout:** three panes. A sidebar of tags and facets, an item list, and a detail pane that edits the item and shows the rendered page.

  ```
  ┌──────────┬───────────────────┬──────────────────┐
  │ 🔍       │ How CloudKit Sync │ How CloudKit Sync│
  │ All  214 │   example.com     │ Works            │
  │ Untagged │ SwiftUI Lists     │ tags: [swift][+] │
  │ ──────── │   swiftbysundell  │ note: …          │
  │ swift 42 │ Defuddle README   │ ──────────────── │
  │ ios   31 │   github.com      │ rendered page…   │
  │ ai     7 │                   │                  │
  └──────────┴───────────────────┴──────────────────┘
  ```

- **Filtering:** the same rules as idea 2 (AND tags, free text, kind/site/untagged/date facets, narrowing counts). In the manager, the sidebar plays the role of the chip bar.
- **Editing:** tags (with autocomplete), note, and title. Single-item actions: open, copy Markdown, export `.md`, and delete (FR-7).
- **Not in this idea:** bulk multi-select actions (later), and editing the Markdown body.
- **Entry point:** the "Open library" link in the popup.

## Open questions

- **Where Safari on macOS gets its data (spike):** either (a) a native-messaging read/write API to SatchelKit's App Group store, so all three browsers share one web UI, or (b) the Mac app is the manager and the extension just opens it. (b) means less code; (a) means one UI everywhere.
- **Narrow windows:** collapse to two panes, then one?
- **Title edits:** does an edited title stick when the page is saved again (FR-6), or does the new capture win? The merge rules in §7.3 need a line for this.

## Comments
