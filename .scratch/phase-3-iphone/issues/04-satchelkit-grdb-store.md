# SatchelKit: GRDB store and outbox in the App Group

Status: resolved
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

## Answer

GRDB **7.11.1** (`exact:` in `apple/SatchelKit/Package.swift`, revision pinned in `Package.resolved`): the newest 7.x release, published 2026-06-18, so well past a 14-day minimum age. `Store` lives in `apple/SatchelKit/Sources/SatchelKit/` (`Store.swift`, `StoreSchema.swift`, `StoreTypes.swift`, `SearchPattern.swift`, `MergeResult.swift`).

- **Opening:** `Store(url:changeNotificationName:merge:)` opens a `DatabasePool` (WAL, persistent WAL, a 10 s busy timeout, `observesSuspensionNotifications`) inside an `NSFileCoordinator` write and runs the `DatabaseMigrator`, following GRDB's "Sharing a Database" guide. `Store(environment:merge:)` puts the file at `<App Group container>/Library/Application Support/Satchel/satchel.sqlite`, using `AppEnvironment.appGroup`.
- **Tables (migration `v1`):**
  - `items`: Item JSON plus `kind`, `createdAt`/`updatedAt` (with parsed epoch columns for sorting), `metadataStatus`, and the search columns. `seq INTEGER PRIMARY KEY` is the FTS rowid.
  - `itemTags (itemID, tag)`, indexed by tag.
  - `bodies`: Markdown by item ID.
  - `outbox`: id, item ID, `upsert`/`delete`, payload (the merged Item JSON), `state`, attempts, last error, timestamps.
  - `syncState`: key/value blobs for ticket 07.
- **Migrations** must be additive, because an older extension process may open a newer file. A store opens a file with migrations it doesn't know.
- **Merge is injected:** `ItemMerge = @Sendable (Item, Item) throws -> MergeResult`, called as `merge(stored, incoming)`. `MergeResult` (`item`, `body: .a/.b/.none`, `replacesBody`) matches `packages/model`'s `MergeResult` and its JSON keys, so ticket 03's `SatchelModel.merge` can decode and return it directly. The body follows the merge: `.a` keeps the stored body, `.b` takes the incoming body (or keeps the stored one if none was passed), and `.none` drops it. A merge that throws or changes the ID rolls the transaction back.
- **API** (all `async throws`):
  - `save(item:body:) -> Item` merges, writes the item, tags, and body, reindexes, and queues an `upsert`, all in one transaction.
  - Reads: `item(id:)`, `body(for:)`, `items(matching:filter:)`, `tags(prefix:limit:)` (most used first).
  - `delete(id:) -> Bool` deletes locally and queues a `delete`.
  - Outbox: `pendingOutbox(limit:)` returns `pending` and `failed` entries, oldest first. `markSent(_:)`, `markFailed(_:error:)`, and `outboxState(for:)` manage state.
  - Sync state: `syncState(forKey:)` and `setSyncState(_:forKey:)`.
  - `ItemFilter` filters by kind, tag, and metadata status, with order `recentlyUpdated` (the default), `recentlyCreated`, or `relevance`, plus a limit.
- **Outbox:** the store keeps one entry per item. A new save or delete replaces the earlier entry, so a sender's late `markSent` for a replaced entry does nothing, and the outbox stays bounded. `sent` is final.
- **Search:** external-content FTS5 (`itemsFTS`, content = the `itemSearch` view over items ⨝ bodies) over title, description, site (the site name plus the host without `www.`), tags, and body. It uses `unicode61 remove_diacritics 2` with `prefix='2 3'`. The store keeps the index in sync with explicit `'delete'` and insert statements that read the same view, and the tests run FTS5's `integrity-check`. User input becomes quoted prefix terms (`kay` → `"kay"*`, ANDed), so FTS syntax never parses.
- **Observation:** `observeItems(matching:filter:)` and `observeUnsentOutbox()` return `AsyncSequence`s backed by GRDB `ValueObservation`. GRDB can't see writes from other processes, so every write posts a Darwin notification (`<appGroup>.store.changed`), and each `Store` answers one with `notifyChanges(in: .fullDatabase)`, which refreshes its observations.
- **Left for the app:** posting `Database.suspendNotification` and `resumeNotification` around suspension (ticket 06/07). Applying remote changes without queuing an outbox entry is ticket 07's call; `save` always queues one today.

**Tests** (`Tests/SatchelKitTests/StoreTests.swift`, 34 new tests) cover:
- migrations and WAL mode, reopening, and opening a file a newer version migrated
- a save-then-read round trip of every contract fixture
- merge on re-save, merge argument order, body choices, and rollback
- FTS on each field, prefixes, diacritics, AND, injection strings, reindexing, and relevance
- filters and ordering, tags, and sync state
- outbox transitions, replacement, and deletes
- two `Store`s on one file writing concurrently (80 items plus one contended item), and one observing the other's save and outbox change
