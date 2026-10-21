# Phase 1: Capture engine

Source: `docs/spec.md` §4 (capture engine), §5 (Markdown format), §7 (data model), §9.1.4 (renderer), §12.4 (testing), and §14 Phase 1. Follow ADR-0002 (Defuddle), ADR-0003 (Turndown), and Spike C's addendum.

Packages: `packages/model`, `packages/capture`, `packages/render`. All are pure TypeScript. `capture` never touches `window`, `location`, `chrome.*`, or `browser.*`.

## Acceptance criteria (from the spec)

- [ ] Golden tests pass (at least 20 fixtures).
- [ ] Model contract fixtures round-trip in TypeScript.
- [ ] IIFE bundles build and expose `globalThis.SatchelCapture` and `globalThis.SatchelRender`.
- [ ] Timing on the fixture set is logged in CI (informational): `captureLink` well under 50 ms, `capturePage` under 1.5 s.
