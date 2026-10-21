# ADR-0016: Release, CI, and web hosting

- **Status:** Accepted
- **Date:** 2026-10-21

## Context

Satchel needs repeatable iOS releases, CI for both the web and Apple sides (ADR-0001), and a public place for the privacy policy, support page, and possibly a CloudKit sign-in relay page (§8.3, Spike A). The developer already has Chrome Web Store and Edge Partner Center accounts.

## Decision

- **iOS releases** are scripted under `scripts/deploy/`: `xcodebuild archive` then `xcodebuild -exportArchive` with automatic signing, uploaded with an App Store Connect API key kept outside the repo (ADR-0014). Internal TestFlight first.
- **CI** runs on GitHub Actions:
  - Ubuntu: web lint, typecheck, tests, and gitleaks.
  - macOS: XcodeGen generate, simulator build, and `SatchelKit` tests.
  - No signing secrets in CI for now; release builds run on the developer's Mac.
- **Web hosting:** public pages (privacy policy, support, future CloudKit sign-in relay) are published from `site/` to **GitHub Pages** by an Actions workflow, at https://cicorias.github.io/satchel-app/. A custom domain may be added later.

## Consequences

- Releases are reproducible from the command line, with no extra Ruby toolchain.
- CI never holds signing material, which suits a public repo; the trade-off is that archives are not built in CI.
- The privacy policy URL required by all three stores (Phase 7) exists early.
- A future custom domain would change the privacy policy and callback URLs; set it before Phase 7 production tokens if wanted.

## Alternatives considered

- *fastlane:* capable, but adds a Ruby toolchain for what a few `xcodebuild` calls already do.
- *Xcode Cloud:* convenient signing, but splits CI across two systems and cannot run the web jobs.
- *Manual archive from Xcode:* not repeatable or scriptable by agents.
- *Signed CI builds:* possible later; deferred to keep secrets out of a public repo's CI.
- *Custom domain now:* not needed until store submission.
