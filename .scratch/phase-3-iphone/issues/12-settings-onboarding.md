# Settings and onboarding

Status: ready-for-agent
Type: task
Blocked by: 06

§9.2.4 "Onboarding", §8.5, and §11:
- **First run:** a page explaining how to enable the Safari extension (the steps verified in Spike B: Settings → Apps → Safari → Extensions → Satchel), plus iCloud status.
- **Without iCloud:** explain that saves queue locally until iCloud is available.
- **Settings:**
  - the active provider (iCloud only in v1) and account status from ticket 07
  - **Load remote images**, on by default in Debug builds; the store default is open question 4, decided in Phase 7
  - the app version and build
  - links to the privacy policy and support pages on `site/`

**Done when** UI tests cover first-run onboarding and the settings toggle, and the remote-image setting is read by ticket 10's detail view.
