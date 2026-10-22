# SatchelKit: CloudKit record mapping and one-shot save

Status: ready-for-agent
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
