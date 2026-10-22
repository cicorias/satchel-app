# SatchelKit: CloudKit record mapping and one-shot save

Status: resolved
Type: task
Blocked by: 02

Map `Item` and its body to and from `CKRecord` per `apple/CloudKit/Satchel.ckdb` (spec §8.2):
- **Record:** record name = `Item.id`, in the `Library` zone of the private database.
- **Body:** stored in `body` when its UTF-8 size is ≤ 512 KB, otherwise as `bodyAsset` (a temporary file). Writers set exactly one and clear the other; readers check `body`, then `bodyAsset`.
- **JSON fields:** `source` and `page` are JSON strings.
- **Unknown fields:** keep Item fields CloudKit has no column for in the local store; don't drop them silently.

Add a `OneShotSaver` for the extensions (§9.2.2–9.2.3):
- It creates the zone if needed, then calls `modifyRecords` with `.changedKeys` for a single item, within a short timeout.
- It reports success or a typed failure (`notAuthenticated`, `network`, `quotaExceeded`, `serverRecordChanged`, …) so the caller marks the outbox row.
- It never runs CKSyncEngine.

**Done when** unit tests cover the mapping both ways (including the 512 KB boundary and asset reading) without network access, and a manual check on the device (documented in `docs/setup/manual-test-plan.md`) shows a record arriving in the Development environment in CloudKit Console.

## Answer

`apple/SatchelKit/Sources/SatchelKit/CloudKit/` holds four files:
- `ItemRecordMapper.swift`: `Item` + body ⇄ `CKRecord`, plus `ItemRecordMappingError`.
- `CloudKitTimestamp.swift`: ISO 8601 string ⇄ `Date`.
- `CloudDatabase.swift`: the `CloudDatabase` protocol and `CloudKitDatabase`, which wraps a real `CKDatabase`.
- `OneShotSaver.swift`: `OneShotSaver` and `OneShotFailure`.

**API**
- `ItemRecordMapper(zoneName:assetDirectory:)` or `ItemRecordMapper(environment:assetDirectory:)`. The zone comes from `AppEnvironment.cloudKitZone`.
  - `record(for:body:updating:)` builds the record.
  - `item(from:existing:)` and `body(from:)` read it back.
  - `recordID(forItemID:)`.
  - `removeAssetFile(of:)` and `removeAssetFiles(olderThan:now:)` clean up asset files.
- `OneShotSaver(database:mapper:timeout:)` takes a timeout (8 s by default). `OneShotSaver(environment:)` uses the private database of `iCloudContainer`.
  - `save(_:body:) async -> Result<CKRecord, OneShotFailure>`.
  - `delete(id:) async -> Result<Void, OneShotFailure>`. A missing record or zone counts as success.
- `OneShotFailure` cases: `notAuthenticated`, `network`, `quotaExceeded`, `serverRecordChanged(CKRecord?)`, `zoneNotFound`, `timedOut`, `invalidItem(String)`, `other(String)`. Its `description` is meant for the outbox row's last error.

**Record**
- Type `Item`, record name = `Item.id`, zone `Library` owned by the current user.
- Every field in `Satchel.ckdb` maps to the `Item` property with the same JSON key. A test parses the `.ckdb` file and checks that the mapper's field list matches it exactly.
- `source` and `page` are JSON written by the Codable types (sorted keys), so the `extra` fields inside them and inside each image survive.
- An empty `tags` list is written as an absent field, because CloudKit reads an empty list back as no value. An absent field reads back as `[]`.

**Absent fields**
- On a new record, the mapper leaves `Item` fields that are nil unset rather than setting them to nil. A `.changedKeys` save from an extension therefore never blanks a value another device wrote, in line with §7.3: an empty value doesn't overwrite a non-empty one.
- On an `updating:` record (a server copy or one rebuilt from system fields, for ticket 07), those fields are set to nil, so the record matches the item exactly.

**Body**
- A body of at most 512 × 1024 UTF-8 bytes goes in `body`. Anything larger goes in `bodyAsset`.
- Whichever field is set, the other is set to nil, so it appears in `changedKeys` and a save clears the server's old copy.
- `body: nil` means the save carries metadata only, and neither field is touched.
- Readers check `body`, then read the asset's file. A missing or non-UTF-8 file throws `unreadableBodyAsset`.

**Asset temp files**
- The mapper writes `<assetDirectory>/<id>-<UUID>.md`. The default directory is `<process tmp>/SatchelBodyAssets/`. The unique name means two saves of one item never share a file.
- After a save completes, whether it succeeded or failed, `OneShotSaver` deletes that save's file.
- After a timeout it keeps the file, because CloudKit may still be uploading it.
- Each save first sweeps files older than an hour, which also catches an extension killed mid-save.
- `removeAssetFile(of:)` only deletes files inside the mapper's directory, never CloudKit's download cache.

**Timestamps**
- `Item` keeps ISO 8601 strings, and the schema uses TIMESTAMP fields.
- Writing parses RFC 3339 (`item.schema.json`'s `date-time`), with or without a fraction and with `Z` or a numeric offset. Anything else, such as a date-only string, makes the item `invalidTimestamp` / `invalidItem` and no network call is made.
- Reading formats the date as `toISOString()` does (UTC, exactly three fractional digits), rounded to the millisecond, which is CloudKit's precision. The fixtures' `2026-10-22T16:40:27.512Z` strings therefore round-trip exactly; a test checks every millisecond of a second.
- Other inputs come back as the same instant in that form: `+02:00` becomes `Z`, `…:27Z` becomes `…:27.000Z`, and digits past the millisecond are rounded.
- When `existing` is passed, a local string that names the same millisecond is kept as written.

**Fields with no CloudKit column:** `Item.extra` (top-level fields from a newer client) and `Item.selection`.
- The schema has no field for either, so they're left out of the record and kept in the local store.
- `item(from:existing:)` copies both from the local copy when the IDs match. Ticket 04's store and ticket 07's sync should always pass `existing`.
- **Follow-up:** `selection` is a known §7.1 field that §8.2 forgot. Adding a `selection INT64` field to `Satchel.ckdb` while the schema is still Development-only would sync it. That change needs its own decision, so this ticket doesn't make it.

**OneShotSaver**
- It never runs CKSyncEngine.
- **Zone:** it saves straight to `Library`. Only if CloudKit answers `zoneNotFound` does it create the zone and retry once. A zone-save `serverRecordChanged` (the zone already exists) is tolerated. The usual save is one round trip, and nothing has to remember whether the zone exists.
- **Policy:** `.changedKeys`.
- **Timeout:** it covers the zone creation and the retry. It's a race between the call and a sleep that returns on time even when the CloudKit call ignores cancellation. A task group would wait for the call to finish.
- **Error mapping:** CKError codes map as follows, unwrapping a `partialFailure`:
  - `notAuthenticated` → `notAuthenticated`
  - `networkUnavailable`, `networkFailure`, `serviceUnavailable`, `requestRateLimited`, `zoneBusy`, `serverResponseLost` → `network`
  - `quotaExceeded` → `quotaExceeded`
  - `serverRecordChanged` → `serverRecordChanged`, carrying the server copy
  - `zoneNotFound`, `userDeletedZone` → `zoneNotFound`
  - a `URLError` → `network`
  - anything else → `other`
- `CloudKitDatabase` runs its calls at `.userInitiated` priority.

**Tests:** 46 new tests in `ItemRecordMapperTests.swift` and `OneShotSaverTests.swift`, with no network access. They cover:
- both directions for every `fixtures/model/*.json`, with and without the local copy
- record name, zone, and type; the field list against `Satchel.ckdb`
- the 512 KB boundary, multi-byte UTF-8, and reading the asset back
- unknown fields in `source` and `page` surviving
- timestamp conversion
- the `OneShotSaver` against an in-memory fake: success, zone creation and retry, every error mapping, a partial failure, a timeout, asset cleanup, and delete

**Still to check by hand:** the device check (a record arriving in Development) is in `docs/setup/manual-test-plan.md` §4. It runs once ticket 06 wires the Share Extension to `OneShotSaver`.
