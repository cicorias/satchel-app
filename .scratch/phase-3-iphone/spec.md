# Phase 3: iPhone app, Share Extension, and Safari

Source: `docs/spec.md` §9.2 (Apple apps), §7 (data model), §8.2–8.3 (CloudKit), §3 (FR-3–FR-8, FR-10, and the §3.2 budgets), §11 (security), and §14 Phase 3. Follow ADR-0004 (CloudKit), ADR-0005 (Safari packaging), ADR-0007 (Safari saves through native code, plus the Spike D addenda), ADR-0011 (iPhone first), ADR-0012 (iOS 26), and ADR-0017 (GRDB).

**Scope: iPhone only** (ADR-0011).
- The macOS host app and Safari on macOS get their own folder when the Mac target is enabled.
- The "Chrome ↔ iOS" round trip is verified in Phase 2.

Targets: `Satchel` (host app), `SatchelShare`, `SatchelSafari`, and `SatchelKit`, all in `apple/project.yml`. Web code comes from `packages/capture`, `packages/render`, and `apps/extension` (the Safari build).

## How the pieces fit

```text
SatchelShare / SatchelSafari handler      host app (Satchel)
  capture (IIFE) → Item + body              CKSyncEngine ⇄ CloudKit "Library" zone
  SatchelKit.Store (GRDB, App Group)  ◀──▶  SatchelKit.Store
    outbox row → one-shot CloudKit save     drains the outbox, merges remote changes,
    (failure leaves it for the app)         enriches pending links, renders the library
```

## Acceptance criteria (from §14 Phase 3, iPhone scope)

- [x] On iPhone, sharing from Safari saves both links and pages.
- [x] Sharing a URL from another app saves a pending link, which the host app later enriches.
- [x] The Safari extension saves links and pages on iOS.
- [x] Saves made with no network sync once the device is back online.
- [x] The library lists, searches, renders, exports, and deletes saved Items (FR-7).

## Tickets

| # | Ticket | Blocked by |
|---|---|---|
| 01 | ~~Decide how Swift gets normalization, IDs, and merge rules~~ → ADR-0020 (JavaScriptCore) | - |
| 02 | SatchelKit: Item model and contract fixtures | - |
| 03 | SatchelKit: normalization, IDs, and merge (per 01) | 01, 02 |
| 04 | SatchelKit: GRDB store and outbox in the App Group | 02 |
| 05 | SatchelKit: CloudKit record mapping and one-shot save | 02 |
| 06 | Tracer bullet: share a URL → outbox → CloudKit → library list | 03, 04, 05 |
| 07 | Host app sync: CKSyncEngine, outbox drain, push, background refresh | 06 |
| 08 | Safari extension: save from the popup through the native handler | 06 |
| 09 | Share Extension from Safari: page mode, tags, and note | 06 |
| 10 | Library: search, filters, detail view, export, delete | 06 |
| 11 | Enrichment of pending links | 06 |
| 12 | Settings and onboarding | 06 |
| 13 | Device acceptance pass (human) | 07–12 |
