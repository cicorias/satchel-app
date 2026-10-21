# ADR-0011: Delivery order — iPhone first

- **Status:** Accepted
- **Amends:** [ADR-0004](0004-cloudkit-first.md) and [ADR-0005](0005-safari-packager.md) (spike timing and phase order)
- **Date:** 2026-10-21

## Context

Spec §14 orders delivery Phase 0 → 1 (capture engine) → 2 (Chrome/Edge) → 3 (Apple apps and Safari). The developer wants the iOS experience first. The Share Extension and Safari extension both depend on the capture engine's IIFE bundle, so the engine cannot be skipped.

## Decision

- **Order:** Phase 0 → Phase 1 (capture engine) → Phase 3 (Apple, iPhone only) → Phase 2 (Chrome/Edge). Phase numbers stay as they are in the spec.
- **iPhone only in Phase 3:** all iPhone sizes supported, tuned for iPhone 18 Pro Max, portrait-first. iPad and macOS targets are deferred; `apple/project.yml` is structured so they can be added without restructuring.
- **Spikes:** Spike A (CloudKit Web Services sign-in from an extension) moves to the start of the Chrome/Edge phase, since nothing before it needs web sign-in. Spikes B (Safari packager), C (Defuddle Markdown extension points), and D (native message size) stay in Phase 0.

## Consequences

- The first usable product is an iPhone app with Share Extension and Safari extension, saving to CloudKit natively.
- The CloudKit schema is first exercised through the native framework; the Web Services adapter (ADR-0004) is validated later. Schema choices must still respect §8.2 so the web client fits without migration.
- The WXT Safari build is the first extension target built, which de-risks ADR-0005 earlier.
- Cross-device acceptance criteria in Phase 3 that involve Chrome ("An Item saved in Chrome appears in the iOS library") move to Phase 2's acceptance.
- macOS-only features (Safari context menus, macOS library page) wait for the Mac target.

## Alternatives considered

- *Spec order (Chrome/Edge before Apple):* delays the platform the developer cares about most and front-loads the riskiest auth spike.
- *A Swift-only link-saving iOS app first, engine later:* faster first build, but the Share/Safari page modes need the capture IIFE anyway, and a separate Swift metadata path would diverge from the shared engine.
