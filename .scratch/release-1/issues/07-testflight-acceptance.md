# TestFlight build and acceptance pass

Status: resolved
Type: task
Blocked by: 01, 02

`../../phase-3-iphone/issues/13-device-acceptance-pass.md` on a **Release** build from TestFlight. This is the first time Production CloudKit and Release defaults get exercised.

1. `mise run deploy:ios-archive`, then `mise run deploy:ios-upload`. Install from TestFlight; it replaces the Debug build.
2. Run `docs/setup/manual-test-plan.md` §4–§5 plus the Phase 3 checks in ticket 13. The records should appear in CloudKit Console under **Production**.
3. Check the Release defaults: remote images are off, so saved pages show "Image not loaded" placeholders, and onboarding appears on first launch.

Anything that fails becomes a new issue here.

## Answer

2026-10-23: the user ran build 61 (version 2026.10.0, Release) from TestFlight on the iPhone 18 Pro Max. Everything passed:
- onboarding on first launch;
- remote images off by default;
- a Safari page share landing in the **Production** CloudKit database;
- a Notes link getting its details;
- Safari extension link and page saves;
- an offline save syncing after reconnecting;
- library search, detail, export, and delete.
