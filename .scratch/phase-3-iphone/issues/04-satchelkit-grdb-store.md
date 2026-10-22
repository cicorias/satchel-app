# SatchelKit: GRDB store and outbox in the App Group

Status: ready-for-agent
Type: task
Blocked by: 02

Add GRDB (ADR-0017, an exact version in `Package.swift`) and a `Store` that the app and both extensions open from the App Group container (`AppEnvironment.appGroup`), in WAL mode (§9.2.1).

- **Tables:**
  - `items`: the Item JSON plus indexed columns for `id`, `kind`, `createdAt`, `updatedAt`, `metadataStatus`, and tags.
  - `bodies`: Markdown by item ID.
  - `outbox`: id, item ID, operation (`upsert`/`delete`), payload, `state` (`pending`/`sent`/`failed`), attempts, last error, timestamps.
  - Sync state: the CKSyncEngine serialized state, used in ticket 07.
- **Migrations** use `DatabaseMigrator`.
- **Search:** an FTS5 index over title, description, site, tags, and body (FR-7).
- **API:** `save(item:body:)` merges with any existing row (§7.3, through ticket 03's merge, or a temporary keep-newest until 03 lands) and enqueues an outbox row in one transaction. Also `items(matching:filter:)`, `body(for:)`, `delete(id:)`, and outbox helpers (`pending()`, `markSent`, `markFailed`).
- **Concurrency:** Swift 6 strict concurrency. A database actor or GRDB's `DatabasePool` must be safe across processes.

**Done when** Swift Testing covers migrations, a save-then-read round trip, merge on re-save, FTS queries, outbox state transitions, and two `DatabasePool`s on the same file (simulating app plus extension) writing concurrently without errors.
