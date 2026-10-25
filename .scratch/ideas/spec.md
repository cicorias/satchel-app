# Ideas: future features, not yet committed

Intake for feature ideas (ADR-0018). Nothing here is planned work, and nothing here overrides `docs/spec.md`.

- **Idea:** one line in the list below, newest at the bottom.
- **Expanded:** a ticket at `issues/NN-<slug>.md` with `Status: needs-triage`, linked from its line here.
- **Accepted:** it gets an FR row in spec §3.1 and a phase in §14, and its tickets move to that phase's folder. Mark the line here `→ accepted (FR-NN)`. Ideas that overlap an existing FR or phase fold into it.
- **UI ideas** get a `Type: prototype` ticket first: iterate on throwaway prototypes with the user before writing any spec.

## Ideas

1. **Auto-tagging** — spike: suggest tags for link and page captures with something lightweight (NLP/NLU, a small model, or Apple's on-device Foundation Models). → [expanded](issues/01-auto-tagging.md)
2. **Tag filtering in the library** — click one or more tags to filter (additive, AND), combined with free-text search. *(UI: prototype first; extends FR-7.)* → [expanded](issues/02-tag-filtering.md)
3. **Full-page library manager in the web extension** — a full-tab view-and-edit page for Safari, Chrome, and Edge, like Chrome's Bookmark Manager or Edge's Favorites, built around tags. *(UI: prototype first; relates to spec §9.1.4.)* → [expanded](issues/03-extension-library-manager.md)
4. **Tag hygiene** — rename and merge tags everywhere, synonyms so suggestions settle on one spelling, and hierarchical tags (`dev/swift`). *(Pairs with idea 1.)* → [expanded](issues/04-tag-hygiene.md)
5. **Smart collections** — save a filter (tags, text, and facets) as a named view in the library. *(Builds on idea 2.)* → [expanded](issues/05-smart-collections.md)
6. **Bulk actions in the manager** — multi-select items to add or remove tags, delete, or export. *(Builds on idea 3.)* → [expanded](issues/06-bulk-actions.md)
7. **Duplicate and dead-link check** — find near-duplicate URLs and saved links that now fail (404, gone), with fix or remove actions. → [expanded](issues/07-duplicates-and-dead-links.md)
