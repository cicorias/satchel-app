# Host app sync: CKSyncEngine, outbox drain, push, background refresh

Status: resolved
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

## Answer

**Code** (`apple/SatchelKit/Sources/SatchelKit/Sync/`)
- `SyncCoordinator` holds the sync logic apart from CKSyncEngine, so tests can drive it with plain `CKRecord`s and `CKError`s through `SyncChangeQueue` (which `CKSyncEngine.State` conforms to).
  - **Outbox → engine:** `enqueueOutbox(into:)` turns every unsent outbox entry into a pending `saveRecord` or `deleteRecord`. A delete replaces a pending save.
  - **Records:** `record(for:queue:)` builds the record from the item as stored, on top of the server's last known system fields, which are archived in `syncState` under `systemFields/<id>`. So CloudKit's change tag catches conflicts. When there's nothing to send, it removes the pending change. A save is marked `sent` only if its outbox entry wasn't replaced by a newer save while it was in flight.
  - **Sent changes:** `handleSent(...)` handles each case:
    - `serverRecordChanged`: merges the server copy into the local item with `SatchelModel.merge` (one JSContext per process) and sends again on the server's change tag.
    - `zoneNotFound` / `userDeletedZone`: saves the zone, then the record again.
    - `unknownItem`: the local save creates the record again.
    - Transient errors: mark the outbox entry failed, and CKSyncEngine retries them itself.
    - `quotaExceeded`: marks the entry failed and queues the save again.
  - **Fetched changes:** `handleFetched(...)` applies them through `Store.applyRemote(_:body:)` and `Store.applyRemoteDeletion(id:)`, which never queue outbox entries.
    - An item with no unsent change takes the server copy as it is, so a tag removed elsewhere stays removed.
    - An unsent local change wins. A local save is merged with the server copy and queued again, a local delete is kept, and a save survives a remote deletion, which re-creates the record.
  - **Zone deleted:** `handleZoneDeleted(reason:)` erases the local copy on `.purged`/`.deleted` (the user removed Satchel's iCloud data) but keeps the account owner. On `.encryptedDataReset` it uploads everything again (`Store.queueAllForUpload()`).
  - **Account:** `checkAccount(userRecordName:)` lets the first account seen own the library and reports `.different` for any other. `forgetServerState()` drops the engine state and system fields but keeps the library and outbox.
- `LibrarySync` is the `CKSyncEngineDelegate` and runs in the host app only.
  - **Start:** `start()` checks `accountStatus` and `userRecordID`, starts the engine with its saved state (`automaticallySync`), saves the `Library` zone on the first run, and queues the outbox.
  - **Outbox:** while the engine runs, it observes the outbox, so saves from the extensions are queued as they happen.
  - **Account changes:** sign-out pauses sync with `.noAccount` and keeps the outbox. Switching to, or signing in with, a different account pauses with `.otherAccount`, so two accounts never share one store. `startOver()` erases the local library for the current account; ticket 12 decides how settings offers it. `CKAccountChanged` restarts a stopped engine.
  - **Status:** `statusUpdates()` streams a `SyncStatus` for ticket 12.
- **Host app:**
  - `AppServices` holds the one shared `Store` and `LibrarySync`.
  - `AppDelegate` registers for remote notifications, starts sync at launch, and fetches on a push.
  - `.onChange(scenePhase)` runs `syncNow()` on foreground and schedules a `BGAppRefreshTaskRequest` (`<bundle>.sync`) on background, which `.backgroundTask(.appRefresh)` handles.
  - The library gained swipe to delete, pull to refresh, and a one-line note when sync isn't working normally.

**Tests:** `SyncCoordinatorTests` has 20 tests, using `FakeQueue` and the real JavaScriptCore merge. They cover:
- queuing the outbox, and a delete replacing a pending save;
- a sent save, and a save made while sending staying pending;
- the conflict merge and resend, a conflict without a server copy, a missing zone, a network failure, and the delete of a missing record;
- a fetched record replacing a synced item, or merging into an unsent save;
- a fetched page bringing its body;
- a local delete winning over a fetched record, a fetched deletion, and a save surviving a fetched deletion;
- account ownership, sign-out, a purged zone, and an encrypted data reset.

SatchelKit has 123 tests in total. The simulator UI suite passes (3/3).

**Device check (2026-10-23, iPhone 18 Pro Max, signed Debug build; `docs/setup/manual-test-plan.md` §5):**
- **First launch:** stored the account and engine state, and fetched the record the Share Extension had saved.
- **Airplane-mode save:** synced after reconnecting.
- **Console edit:** a title change made in CloudKit Console appeared on the phone.
- **Delete:** a swipe-delete removed the record from CloudKit. Its outbox entry was `sent` after 1 attempt, in about 1.5 s.
- **Console `url` edit:** applied to the stored item; a unit test covers it. The row doesn't show it because it shows only the site or host; the detail view comes in ticket 10.

**Known gap for ticket 12:** while the library is paused for `.otherAccount`, the extensions' `OneShotSaver` still writes to whichever account is signed in. Settings should explain this, or the extensions should check the library's owner before saving.
