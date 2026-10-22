# Host app sync: CKSyncEngine, outbox drain, push, background refresh

Status: ready-for-agent
Type: task
Blocked by: 06

Implement sync in the host app only (§9.2.4). The extensions never run it (§9.2.3).

- **CKSyncEngine** against the `Library` zone. Persist its state in the store, map records with ticket 05, and merge fetched changes with ticket 03's `SatchelModel.merge`, which runs in JavaScriptCore (ADR-0020); reuse one context for a whole fetch batch. On a `serverRecordChanged` conflict, merge the server record into the local one and send it again.
- **Outbox drain:** on launch, on foreground, from `BGAppRefreshTask` (`<bundle>.sync`, already in Info.plist), and after CloudKit push notifications (`remote-notification` background mode; register for pushes).
- **Deletes:** a delete in the library becomes a pending deletion in the engine, and a remote deletion removes the local row.
- **iCloud account changes:** handle sign-out and switching accounts. Pause sync, keep the outbox, and report status for ticket 12. Never mix two accounts' data in one store.

**Done when**:
- Saves made in airplane mode sync after reconnecting (acceptance criterion).
- An edit made on one simulator or device appears on another signed into the same iCloud account.
- The conflict path is unit-tested with a fake engine.

## Comments

Notes carried over from tickets 04 and 05 (2026-10-22):
- **Applying remote changes:** `Store.save` always queues an outbox `upsert`, so applying remote changes needs a variant that doesn't, and remote deletions need a path that removes the row without queuing a `delete`.
- **Unknown fields:** use `ItemRecordMapper.item(from:existing:)` with the local copy, so `extra` and `selection` (which have no CloudKit column) survive a fetch.
- **Sync state:** persist CKSyncEngine state through `Store.syncState(forKey:)`/`setSyncState`.
