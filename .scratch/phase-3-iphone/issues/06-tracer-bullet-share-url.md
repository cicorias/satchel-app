# Tracer bullet: share a URL from any app → outbox → CloudKit → library list

Status: ready-for-agent
Type: task
Blocked by: 03, 04, 05

The thinnest end-to-end path through every layer, before any feature work:

1. In **SatchelShare**, accept a URL from any app. Build a link `Item` with `metadataStatus: pending`, `source.client: ios-share`, and the ID from ticket 03. Save it through `Store` (outbox row), attempt `OneShotSaver`, mark the row, and dismiss with a confirmation. Use a minimal UI for now: a "Save link" button.
2. In the **host app**, replace the placeholder `LibraryView` with a list read from `Store`, newest first, observed with GRDB `ValueObservation`, so a save from the extension appears without a relaunch. Show pending and failed outbox state on each row (FR-8).
3. Make sure the entitlements, the App Group, and the iCloud container work in all three targets on a signed device build.

**Done when**:
- On the iPhone, sharing a link from Notes (not Safari) shows it in Satchel's list within a second of returning to the app.
- The record is in CloudKit Console.
- A UI test covers the simulator half of this (share sheet → list).
