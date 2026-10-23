# Manual test plan

These checks aren't automated yet, or need a real device. Use them before a TestFlight build and after Safari or iOS updates. The automated version of 1–2 is `mise run test:ios-ui`.

## 1. Enable the Safari extension (iPhone)

1. Install the app (`mise run run:ios` on a simulator, or a signed device build).
2. Open **Settings → Apps → Safari → Extensions → Satchel**, and turn on **Allow Extension**.
3. Expected: Satchel's icon and the description from `config/app.config.json` are shown, and the switch stays on.

## 2. Open the popup

1. In Safari, open any article page (e.g. https://example.com).
2. Tap the **page menu** button (left side of the bottom tab bar). If the page switches into Reader mode instead, tap it again.
3. Tap **Satchel**.
4. Expected: a sheet with the Satchel header, the page title, **Save link** and **Save page** buttons, and a status line.

## 3. Native messaging (device)

On a device, repeat the Spike D measurement (ADR-0007 addendum). It needs temporary probe code; see `.scratch/phase-0-foundations/issues/08-verify-native-messaging-on-device.md`.

## 4. CloudKit one-shot save (device)

`OneShotSaver` (`apple/SatchelKit`, Phase 3 ticket 05) is unit-tested against a fake database only. This check confirms that a real save reaches CloudKit. It needs the signed device build from ticket 06, where the Share Extension saves through `OneShotSaver`.

**Before you start**
- The iPhone is signed in to iCloud, with iCloud enabled for Satchel (**Settings → [your name] → iCloud → Apps Using iCloud**).
- The schema is in Development: `mise run deploy:cloudkit-schema diff` shows no changes.
- The build is a Debug build signed for development, so it talks to the **Development** environment.

**Save a link**
1. In Notes, put a URL you haven't saved before (e.g. `https://example.com/satchel-check-<today>`) in a note, then share it to **Satchel** and tap **Save link**.
2. Expected: the confirmation appears within a few seconds (the saver gives up after 8 s), and the row in Satchel's list doesn't show a pending or failed state.

**Find the record in CloudKit Console**
1. Open [CloudKit Console](https://icloud.developer.apple.com) → **CloudKit Database** → container `iCloud.com.cedarlogic.satchel` → **Development**.
2. Private data belongs to the device's iCloud account. If you signed in to the Console with a different Apple ID, choose **Act as iCloud Account** and sign in as the device's account.
3. Go to **Records**, choose database **Private**, zone **Library**, and record type **Item**. Query all records (this relies on the queryable `recordName` index in `Satchel.ckdb`).
4. Expected, in the record you just saved:
   - Its record name is the item's ID: `u_` followed by 32 hex characters.
   - `kind` is `link`, `metadataStatus` is `pending`, `url` and `normalizedUrl` hold the shared URL, and `title` is set.
   - `createdAt` and `updatedAt` show the time of the save (the Console shows your local time zone).
   - `source` is JSON along the lines of `{"client":"ios-share","version":"2026.10.0"}`.
   - `body` and `bodyAsset` are both empty for a link. `tags` is empty unless you added tags.
5. **Zones** lists `Library`. If you reset the Development environment first, this confirms the saver created the zone on its first save.

**Failure paths (optional, but worth doing once)**
- **Offline:** turn on Airplane Mode and share another URL. The save should fail quickly with `network`, not hang for 8 s, and the row should stay pending. Turn Airplane Mode off and open Satchel: the host app's sync should send it (ticket 07).
- **Signed out of iCloud:** the save fails with `notAuthenticated`, and the item stays in the local list.
- **Large page (after ticket 09):** save a page whose Markdown is over 512 KB. Its record has a `bodyAsset` and an empty `body`. Re-saving a smaller version clears `bodyAsset` and sets `body`.

## 5. Host app sync (device)

`LibrarySync` (CKSyncEngine, Phase 3 ticket 07) is unit-tested through `SyncCoordinator` with a fake change queue. These checks run the real engine. Use the same signed Debug build and iCloud account as §4.

**Offline save syncs after reconnecting** (acceptance criterion)
1. Turn on Airplane Mode. Share a new URL from Notes to Satchel and tap **Save link**. The sheet says "Saved — will sync later".
2. Open Satchel: the row shows **Not synced yet**.
3. Turn Airplane Mode off and stay in Satchel, or pull to refresh. The badge goes away within a few seconds, and the record is in CloudKit Console.

**A change from another device appears**
1. In CloudKit Console (§4, steps 1–3), open one of the records, change its `title`, and save. Another signed-in device or simulator works the same way.
2. With Satchel open, the new title appears within about a minute through the CloudKit push, or right away after a pull to refresh.

**Delete**
1. Swipe left on a row in Satchel and tap **Delete**.
2. Query again in the Console: the record is gone.

**Checking the local state.** Copy the store off the device and inspect the outbox, which should hold no unsent entries once everything is synced:
```sh
for f in satchel.sqlite satchel.sqlite-wal satchel.sqlite-shm; do
  xcrun devicectl device copy from --device <UDID> --domain-type appGroupDataContainer \
    --domain-identifier group.com.cedarlogic.satchel \
    --source "Library/Application Support/Satchel/$f" --destination "apple/build/device-db/$f"
done
sqlite3 apple/build/device-db/satchel.sqlite "SELECT itemID, operation, state, lastError FROM outbox"
```

## Later phases

Safari page saves and the full device acceptance pass get added here in Phase 3 (spec §14).
