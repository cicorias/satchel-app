# Apple portal, CloudKit, and App Store Connect setup

Status: ready-for-human
Type: task
Blocked by: -

Follow `docs/setup/apple.md` §1–5: identifiers (App Group, iCloud container, three App IDs), signing certificates, CloudKit record type and indexes (Development), App Store Connect app record, TestFlight group, and the API key.

## Done when

- `SIGNED=1 DESTINATION="platform=iOS,name=<your iPhone>" mise run build:ios` succeeds and the app runs on your iPhone.
- Anything in `docs/setup/apple.md` that was wrong or unclear is fixed. Record it under `## Comments` here and the agent will update the doc.
- If the App Store rejects "Satchel" as a name, the name you chose is recorded in `config/app.config.json`.
