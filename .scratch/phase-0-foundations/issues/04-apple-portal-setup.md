# Apple portal, CloudKit, and App Store Connect setup

Status: resolved
Type: task
Blocked by: -

Follow `docs/setup/apple.md` §1–5: identifiers (App Group, iCloud container, three App IDs), signing certificates, the CloudKit schema (Development, via a management token and `mise run deploy:cloudkit-schema import`), App Store Connect app record, TestFlight group, and the API key.

## Done when

- `SIGNED=1 DESTINATION="platform=iOS,name=<your iPhone>" mise run build:ios` succeeds and the app runs on your iPhone.
- Anything in `docs/setup/apple.md` that was wrong or unclear is fixed. Record it under `## Comments` here and the agent will update the doc.
- `mise run deploy:cloudkit-schema validate` passes, and `mise run deploy:cloudkit-schema diff` reports no differences (§4 step 4).
- If the App Store rejects "Satchel" as a name, the name you chose is recorded in `config/app.config.json`.

## Answer

Done on 2026-10-22. The identifiers, certificates, App Store Connect record, TestFlight group, and API key are all in place. Build 19 went through `deploy:ios-archive` and `deploy:ios-upload`, and it installs from TestFlight on an iPhone 18 Pro Max. The CloudKit Development schema matches `apple/CloudKit/Satchel.ckdb` (`deploy:cloudkit-schema diff` shows no differences).

There were two problems along the way, and neither came from `docs/setup/apple.md`:

- CloudKit §4 was moved from Console clicks to `xcrun cktool` (ADR-0004 addendum).
- The first upload was rejected with ITMS-90474 because XcodeGen's per-target preset set `TARGETED_DEVICE_FAMILY` to `1,2`. It was fixed in `645e958` with the `iphoneOnly` setting group, and `ios-archive.sh` now fails fast on it.

That unblocks 08.
