# Tag filtering in the library

Status: needs-triage
Type: prototype
Blocked by: -

Filter the library by one or more tags combined with free-text search. This extends FR-7 and the "filters by tag and kind" line in spec §9.2.4. Expanded from idea 2 on 2026-10-25.

## Decisions so far

- **Layout (iPhone):** a horizontally scrolling chip bar under the search field. Selected tags move to the front with a ✕ to remove them.

  ```
  ┌─────────────────────────────┐
  │ 🔍 Search                   │
  │ [swift ✕][ios ✕] cloudkit ai│
  ├─────────────────────────────┤
  │ How CloudKit Sync Works     │
  │ example.com · swift ios     │
  └─────────────────────────────┘
  ```

- **Logic:** AND only. Each tag narrows the results, and free text narrows them further.
- **Narrowing:** after a selection, the bar shows only tags that appear on the matching items, with counts (`ios 12`), so a filter can never return zero results.
- **Order:** unselected tags by item count in the current results.
- **Other facets:** kind (link/page), site/domain, untagged, and date range (this week, this month, custom). They're reached from a filter button next to the search field. Active facets appear as chips in the same bar (`[page ✕]`, `[this month ✕]`).
- **Tap to filter:** tapping a tag on a row or in the detail view adds it to the active filter. Tapping a site name filters to that site.

## Prototype questions

- Does a single chip bar stay readable with tags and facets mixed together, or should facets get their own row?
- What happens to the selection after a search returns no matches?
- Untagged combined with tags is a contradiction. Should one disable the other?
- Does the filter state survive leaving the screen? Relaunching the app?

## Notes

- The same filter rules should apply in the extension's library manager (idea 3). Define the rules once, in `packages/model` or alongside it, and run them on iOS through JavaScriptCore (ADR-0020).
- Saved filters ("smart collections") are a separate idea (5).

## Comments
