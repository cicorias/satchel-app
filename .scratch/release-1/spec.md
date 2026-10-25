# Release 1: Satchel for iPhone on the App Store

Source: `docs/spec.md` §14 Phase 7 (store readiness), iPhone scope only (ADR-0011). Chrome/Edge (Phase 2) and the Mac app follow this release.

## Bookmark (2026-10-23)

**Where development stopped:**
- **Phase 3 (iPhone):** tickets 01–11 are resolved and merged. Ticket 12 (onboarding and settings) is the last build ticket and comes first here. Ticket 13 is the device acceptance pass, done here on TestFlight (issue 07).
- **Phase 1:** ticket 10 (the Defuddle 0.19.5 bump) waits until the release is eligible under pnpm's minimum release age (after 2026-10-24).
- **Open findings:** a page saved from the popup showed one image twice in a row. It needs a look, and a capture fix would need a fixture (Phase 3 ticket 08's notes).

**After this release:** Phase 2 (Chrome and Edge, [`.scratch/phase-2-chrome-edge/`](../phase-2-chrome-edge/spec.md), opened 2026-10-25; ticket 01 first), then the Mac app.

## Decisions

- **Remote images in store builds:** off by default (open question 4, decided 2026-10-23). Debug builds stay on, as spec §11 says.
- **Version:** the first release is `2026.10.0` (ADR-0015). The build number is the commit count, and each TestFlight upload gets a higher one.

## Done when

- Satchel is live on the App Store for iPhone.
- `docs/spec.md` §14 Phase 7's iPhone boxes are ticked: the Production schema, the privacy policy, review notes, the remote-image default, and the archive script.
