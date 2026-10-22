# Device acceptance pass on iPhone

Status: ready-for-human
Type: task
Blocked by: 07, 08, 09, 10, 11, 12

Run the Phase 3 acceptance criteria (`../spec.md`) on a physical iPhone from a TestFlight build (`mise run deploy:ios-archive` then `deploy:ios-upload`), following `docs/setup/manual-test-plan.md`. The agent extends that plan with Phase 3 steps while working on tickets 06–12.

Check:
- sharing from Safari (link and page)
- sharing a URL from another app, then enrichment
- the Safari extension (link and page)
- airplane-mode saves syncing later
- search, detail, export, and delete
- a second device on the same iCloud account

**Done when** every acceptance box in `../spec.md` is ticked, and anything that failed is a new ticket under `## Comments` here.
