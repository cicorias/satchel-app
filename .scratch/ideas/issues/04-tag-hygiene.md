# Tag hygiene: rename, merge, synonyms, hierarchy

Status: needs-triage
Type: task
Blocked by: -

Keep the tag vocabulary tidy, especially once auto-tagging (idea 1) starts adding tags. Expanded from idea 4 on 2026-10-25.

## Decisions so far

- **Rename and merge:** these rewrite the tags on every affected item, and the normal sync and merge rules carry the change. There's no new CloudKit record type for this.
- **Hierarchy:** tags are plain strings containing `/` (`dev/swift`), so the schema doesn't change. Filtering by a parent includes its children: `dev` matches `dev/swift` and `dev/js`. Sidebars and chip bars show the nesting.
- **Synonyms:** Satchel suggests likely pairs (`ml` / `machine-learning`, `js` / `javascript`) and you confirm a merge or an alias. Auto-tagging (idea 1) maps suggestions through the aliases, so they settle on one spelling.
- **Where it lives:**
  - The iPhone app gets a Tags screen: every tag with its count, and swipe to rename, merge, or delete.
  - The extension manager (idea 3) gets the same actions on the sidebar: right-click to rename or merge, or drag one tag onto another to merge.

## Open questions

- **Rename versus offline edits:** tags merge by union (spec §7.3). If another device edits an item offline while it still has the old tag, the old tag comes back after the rename. Does a rename need a tombstone-style "renamed from" rule, or is an occasional reappearing tag acceptable?
- **Where aliases are stored:** aliases have to sync, but they aren't Items. Options: a small settings record in CloudKit, or a reserved record in the `Library` zone. This is the one schema question in this idea.
- **Hierarchy limits:** how deep can nesting go? Should renaming a parent also rename its children?

## Comments
