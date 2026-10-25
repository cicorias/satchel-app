# First update after release 1

Status: needs-triage
Type: task
Blocked by: 08

Release 1 shipped build 61 (2026.10.0). This list is what's waiting for the next build:

- **Fix: the open library didn't show saves from the extensions.** If a save came from the share sheet or the Safari extension while Satchel was in the background, the library showed it only after a relaunch. The fix is on `main` (`Store.resume()` refreshes every store; `StoreTests.resumingRefreshesObservations`). It was found while recording the app preview.
- **Liquid Glass icon:** PR #23 (`feat/liquid-glass-icon`). It's ready, but the user held it until release 1 is approved.
- **App preview video:** `mise run art:preview` makes `apple/build/preview/app-preview-886x1920.mp4`. Upload it in the large-display iPhone slot with the next version, if it isn't already uploaded.
- **Version:** `2026.10.1` if this ships in October, `2026.11.0` from November (ADR-0015). Bump `version` in `config/app.config.json`.
- **Open finding:** a page saved from the popup showed one image twice in a row (Phase 3 ticket 08's notes).

To ship it: `mise run deploy:ios-archive` and `deploy:ios-upload`, a quick TestFlight check, then a new version in App Store Connect with the same listing text.
