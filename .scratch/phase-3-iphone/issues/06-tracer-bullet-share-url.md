# Tracer bullet: share a URL from any app → outbox → CloudKit → library list

Status: resolved
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

## Comments

Notes carried over from tickets 04 and 05 (2026-10-22):
- **The Xcode project must resolve GRDB** (7.11.1) once SatchelKit is linked into the targets. `project.yml` already lists SatchelKit as a package.
- **Wiring:** open the store with `Store(environment:merge: SatchelModel.bundled().itemMerge)`, and save through `OneShotSaver(environment:)`. Map `OneShotFailure` onto `markSent`/`markFailed`.
- **Suspension:** post GRDB's `Database.suspendNotification`/`resumeNotification` around app and extension suspension, or iOS can kill the process for holding a database lock (0xDEAD10CC).
- **iCloud in the extensions:** both extension targets need the iCloud entitlement, or `CKContainer(identifier:)` fails. They already have it in `project.yml`; check it on the signed device build.
- **Device check:** run `docs/setup/manual-test-plan.md` §4 (CloudKit one-shot save) here.

## Answer

**Code**
- `SatchelKit/ItemSaver.swift` is the shared write path. `ItemSaver.standard()` opens the App Group `Store` with `SatchelModel.bundled().itemMerge` and builds an `OneShotSaver(environment:)`.
  - `saveLink(url:title:tags:note:client:)` builds a pending link `Item`; the title falls back to host + path.
  - `save(_:body:)` writes the item to the `Store` (which adds an outbox row), tries `OneShotSaver`, and marks the row `sent`, or `failed` with `OneShotFailure.description`. It returns `.saved` or `.queued(failure)`.
- `Store.suspend()` / `resume()` post GRDB's suspension notifications. The host app calls them on scene-phase changes; the Share Extension calls them around its save and its dismissal.
- `SatchelShare/ShareViewController.swift` takes the first web URL from the shared items (a `public.url`, or a link found in plain text) and shows a SwiftUI sheet with a "Save link" button. It confirms with "Saved" or "Saved — will sync later" and dismisses itself after 700 ms.
- `Satchel/LibraryModel.swift` + `LibraryView.swift` show the library newest first. It observes `observeItems` and `observeUnsentOutbox` together, so a save from the extension appears without a relaunch, and each row shows a "Waiting to sync" or "Not synced yet" badge (FR-8).

**Signing for simulator builds.** Unsigned builds (`CODE_SIGNING_ALLOWED=NO`) embed no entitlements, so the App Group container is nil and the Store can't open. `build:ios` and `test:ios-ui` now sign ad hoc (`CODE_SIGN_IDENTITY=-`), which needs no certificate.

**Tests**
- `ItemSaverTests` (5 tests): sent path, queued on `notAuthenticated`, re-share merge, shared title, non-HTTP rejected. SatchelKit has 103 tests in total.
- `ShareExtensionUITests.testSharingALinkSavesItToTheLibrary`: Safari → share sheet → Satchel → Save link → the row appears in the app. The full UI suite passes (3/3).

**Device check (2026-10-23, iPhone 18 Pro Max, signed Debug build)**
- **Setup:** the signed entitlements of all three targets include the App Group, the iCloud container, and the keychain group.
- **Steps:** shared `https://www.example.org/satchel-test?utm_source=notes` from Notes to Satchel. The sheet showed "Saved", which appears only after CloudKit returns the saved record.
- **Result:** the App Group database, copied off the phone with `devicectl device copy from`, has:
  - outbox row 1 in state `sent`, after 1 attempt with no error. It was written at 12:46:42.693 and marked sent at 12:46:45.428 (UTC), so the CloudKit round trip took about 2.7 s on first use.
  - item `u_8d6f9c2ab81383061670d650b1bf3036`, which matches `sha256("https://example.org/satchel-test")`: `www.` and `utm_source` were stripped.
  - `source.client: ios-share`, and the title "Example Domain", which came from Notes' link preview.
