# Model: Item types and JSON Schema

Status: resolved
Type: task
Blocked by: -

Implement the `Item`, `ImageRef`, `ClientId`, and related types from spec §7.1 in `packages/model`, plus a JSON Schema (generated from the types or hand-written, then tested against them). Add the first `fixtures/model/*.json` contract fixtures (a link item, a page item, and one with unknown extra fields).

**Done when** the fixtures validate against the schema and round-trip losslessly in Vitest.

## Answer

Done on the `phase-1-capture-engine` branch.

- **Types:** `packages/model/src/item.ts` holds `Item`, `ImageRef`, `ItemSource`, `PageInfo`, `ClientId`, and the enums.
- **Schema:** it's hand-written in `packages/model/schema/item.schema.json` (draft 2020-12), and the package exports it as `@satchel/model/schema/item.schema.json`.
  - Unknown properties are allowed at every level.
  - It enforces the `u_` + 32-hex ID, `http(s)` URLs, ISO 8601 timestamps, and lowercase, trimmed, unique tags.
- **Drift guard:** the `*_SHAPE` maps record every property and whether it's required. The compiler checks them against the types, and a test checks them against the schema, so a property added to one side and not the other fails `typecheck` or `test`.
- **Fixtures:** `fixtures/model/link-minimal.json`, `page-full.json`, and `unknown-fields.json`. Their IDs are the real SHA-256 values, so 02 can reuse them.
- **Validation:** only the tests validate, with `ajv` and `ajv-formats` as dev dependencies. That keeps them out of the capture IIFE.
- **Decision:** `readingMinutes` is an integer (round up) in the schema.

The Swift side of the contract (SatchelKit decoding the same fixtures) is part of Phase 3.
