# Apple portal, CloudKit, and App Store Connect setup

Status: ready-for-human
Type: task
Blocked by: -

Follow `docs/setup/apple.md` §1–5: identifiers (App Group, iCloud container, three App IDs), signing certificates, the CloudKit schema (Development, via a management token and `mise run deploy:cloudkit-schema import`), App Store Connect app record, TestFlight group, and the API key.

## Done when

- `SIGNED=1 DESTINATION="platform=iOS,name=<your iPhone>" mise run build:ios` succeeds and the app runs on your iPhone.
- Anything in `docs/setup/apple.md` that was wrong or unclear is fixed. Record it under `## Comments` here and the agent will update the doc.
- `mise run deploy:cloudkit-schema validate` passes, and the first-run export diff (§4 step 4) is reconciled into `apple/CloudKit/Satchel.ckdb`.
- If the App Store rejects "Satchel" as a name, the name you chose is recorded in `config/app.config.json`.
