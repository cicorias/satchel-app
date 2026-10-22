# SatchelKit: Item model and contract fixtures

Status: ready-for-agent
Type: task
Blocked by: -

Add `Item`, `ImageRef`, `ItemSource`, `PageInfo`, `ClientId`, `MetadataStatus`, and `ImageStatus` (spec §7.1) to `apple/SatchelKit`, mirroring `packages/model/src/item.ts` and `schema/item.schema.json`. Use Codable, with ISO 8601 dates kept as the strings the JSON holds, so they round-trip byte-for-byte.

- **Unknown fields must survive** (§7.1 contract fixtures, `fixtures/model/unknown-fields.json`) at every level. That means a custom `Codable` that keeps the unrecognized keys as raw JSON (for example, `[String: JSONValue]`) and writes them back.
- Replace the placeholder `ItemKind.swift`.
- Make `SatchelKit` read `fixtures/model/*.json` in its tests (resource path from `#filePath`, or copied resources) so both languages test the same files.

**Done when** Swift Testing decodes and re-encodes every `fixtures/model/*.json` losslessly: the same JSON value and the same key set at every level. `mise run verify:apple` passes.
