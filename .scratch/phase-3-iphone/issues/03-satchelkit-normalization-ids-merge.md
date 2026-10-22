# SatchelKit: normalization, IDs, and merge rules

Status: ready-for-agent
Type: task
Blocked by: 01, 02

Implement ADR-0020 (from ticket 01) in SatchelKit: `normalizedURL(pageURL:canonicalURL:)`, `itemID(for:)`, and `merge(_:_:) -> MergeResult` with `body` and `replacesBody`, matching `packages/model`.

- Export shared vectors from the TypeScript tests (normalization inputs and outputs, IDs, and merge pairs with results) to `fixtures/model/`, and test both languages against them. That way neither side can drift, whichever option ADR-0020 picks.

**Done when** Swift passes every shared vector, the TypeScript tests also run against the exported vectors, and the commutativity property holds on the Swift side.
