# Bulk actions

Status: needs-triage
Type: task
Blocked by: 03

Multi-select in both libraries. Expanded from idea 6 on 2026-10-25.

## Decisions so far

- **Actions:** add tags, remove tags, and delete.
- **Delete:** offers undo through a toast, with no confirmation dialog. Deletion is held back until the toast is dismissed, then written as tombstones (spec §7).
- **Where:**
  - The extension manager (idea 3): checkboxes in the item list, and shift-click to select a range.
  - The iPhone library: Edit mode.
- **Not in this idea:** exporting a selection (FR-11 covers exporting the whole library).

## Open questions

- Can a bulk change be undone after the toast is gone, in a single step?
- "Select all" with a filter active: does it mean all matching items, or only the ones loaded on screen?

## Comments
