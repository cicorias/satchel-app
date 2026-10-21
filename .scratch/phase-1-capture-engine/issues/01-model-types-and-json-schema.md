# Model: Item types and JSON Schema

Status: ready-for-agent
Type: task
Blocked by: -

Implement the `Item`, `ImageRef`, `ClientId`, and related types from spec §7.1 in `packages/model`, plus a JSON Schema (generated from the types or hand-written, then tested against them). Add the first `fixtures/model/*.json` contract fixtures (a link item, a page item, and one with unknown extra fields).

**Done when** the fixtures validate against the schema and round-trip losslessly in Vitest.
