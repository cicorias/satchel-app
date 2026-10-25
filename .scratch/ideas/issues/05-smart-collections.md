# Smart collections

Status: needs-triage
Type: task
Blocked by: 02

A smart collection is a saved filter (tags, text, and facets from idea 2) with a name. Expanded from idea 5 on 2026-10-25.

## Decisions so far

- **Where they appear:**
  - iPhone: at the top of the library, above the chip bar.
  - Extension manager (idea 3): a "Collections" section in the sidebar, above the tags.
  - Saving: the save sheet, share sheet, and popup can save into a collection, which applies that collection's tags to the new item.
- **Sync:** through CloudKit, so the same collections appear on every device. This needs a new record type in `apple/CloudKit/Satchel.ckdb` and in spec §8.2, an ADR, and support in `CloudKitWebProvider` for Chrome and Edge.
- **Built-in collections:**
  - Recently saved: the last 7 days.
  - Untagged.
  - Pending: not yet synced or not yet enriched (FR-8).

  These are fixed views. They aren't stored as records.

## Open questions

- **Saving into a collection** only works cleanly when the collection's filter is tags. When it also uses text, a site, or a date, the new item may not match it. Should those collections still be save targets, applying only their tags?
- **Order and pinning:** manual order, or by recent use? Can you hide the built-ins?
- **The filter format** is stored as data that every platform reads, so it needs a version field.

## Comments
