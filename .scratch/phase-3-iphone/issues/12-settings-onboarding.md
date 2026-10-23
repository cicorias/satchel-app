# Settings and onboarding

Status: resolved
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

## Answer

**Onboarding** (`OnboardingView`) appears on first run as a full-screen cover, and again from Settings → How to Save. It covers the Safari extension steps (Settings → Apps → Safari → Extensions → Satchel → Allow Extension → All Websites → page menu → Satchel), sharing from any app (add Satchel via More), and iCloud status, with the note that saves always work offline and sync later.

**Settings** (`SettingsView`):
- **Sync:** status from `LibrarySync`, through `SyncStatus.explanation`. A library owned by another account offers "Use This iCloud Account…", which calls `startOver()` after a confirmation.
- **Load Remote Images:** stored in the App Group defaults (`loadRemoteImages`). It's off in store builds (the release-1 decision) and registered on in Debug. `LibraryModel.loadsRemoteImages` drives the rows and the detail view live.
- **Help:** How to Save, Privacy Policy, and Support. The links come from `SatchelSiteURL` (Info.plist ← `SATCHEL_SITE` in the xcconfig, without `https://` because `//` starts an xcconfig comment) and `AppEnvironment.siteURL`.
- **About:** the version and build.

**Tests:** `SettingsUITests` has two tests.
- `testOnboardingShowsOnFirstRunOnly`: onboarding appears on first run, Get Started closes it, and it doesn't come back on the next launch.
- `testRemoteImagesSettingReachesTheDetailView`: with the switch off, the detail view reports `blocked 2`; with it on, `blocked 0`.

The render report now reads "rendering" until the page renders. Other UI tests pass `-SatchelOnboardingDone`. The UI suite passes 11/11, and verify passes 151 Swift tests.

**Device check (2026-10-23):** the user OK'd onboarding and Settings on the iPhone 18 Pro Max.
