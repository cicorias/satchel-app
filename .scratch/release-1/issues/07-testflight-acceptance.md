# TestFlight build and acceptance pass

Status: ready-for-human
Type: task
Blocked by: 01, 02

`../../phase-3-iphone/issues/13-device-acceptance-pass.md` on a **Release** build from TestFlight. This is the first time Production CloudKit and Release defaults get exercised.

1. `mise run deploy:ios-archive`, then `mise run deploy:ios-upload`. Install from TestFlight; it replaces the Debug build.
2. Run `docs/setup/manual-test-plan.md` §4–§5 plus the Phase 3 checks in ticket 13. The records should appear in CloudKit Console under **Production**.
3. Check the Release defaults: remote images are off, so saved pages show "Image not loaded" placeholders, and onboarding appears on first launch.

Anything that fails becomes a new issue here.
