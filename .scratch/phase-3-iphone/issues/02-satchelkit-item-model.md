# SatchelKit: Item model and contract fixtures

Status: resolved
Type: task
Blocked by: -

Add `Item`, `ImageRef`, `ItemSource`, `PageInfo`, `ClientId`, `MetadataStatus`, and `ImageStatus` (spec §7.1) to `apple/SatchelKit`, mirroring `packages/model/src/item.ts` and `schema/item.schema.json`. Use Codable, with ISO 8601 dates kept as the strings the JSON holds, so they round-trip byte-for-byte.

- **Unknown fields must survive** (§7.1 contract fixtures, `fixtures/model/unknown-fields.json`) at every level. That means a custom `Codable` that keeps the unrecognized keys as raw JSON (for example, `[String: JSONValue]`) and writes them back.
- Replace the placeholder `ItemKind.swift`.
- Make `SatchelKit` read `fixtures/model/*.json` in its tests (resource path from `#filePath`, or copied resources) so both languages test the same files.

**Done when** Swift Testing decodes and re-encodes every `fixtures/model/*.json` losslessly: the same JSON value and the same key set at every level. `mise run verify:apple` passes.

## Answer

`apple/SatchelKit/Sources/SatchelKit/Item.swift` holds `Item`, `ImageRef`, `ItemSource`, `PageInfo`, `ItemKind`, `MetadataStatus`, `ImageStatus`, and `ClientID`. `JSONValue.swift` holds a `JSONValue` enum plus the coding helpers.

- **Round trip:** each type decodes its known keys under `packages/model`'s JSON spelling (`canonicalUrl`, `imageUrl`, …). It keeps every other key as raw `JSONValue` in `extra` and writes those back, so a newer client's fields survive at every level.
- **Strings:** dates stay ISO 8601 strings.
- **Swift names:** follow Swift conventions (`canonicalURL`, `imageURL`, `originalURL`).
- **`ClientID`** is an open, string-backed type with the known values as constants, so an item from a future client (say `safari-visionos`) still decodes. `ItemKind` and the status types stay closed enums, since changing them needs a new schema version.

**Tests** (`Tests/SatchelKitTests/ItemTests.swift`):
- They read `fixtures/model/*.json` straight from the repo, the same files the TypeScript tests use.
- Each fixture decodes, re-encodes to the same JSON value, and decodes again to an equal `Item`.
- Unknown fields survive at the top level and inside `source`, `page`, and the images.
- The known key sets match `packages/model/schema/item.schema.json`, and the enums match the TypeScript model.
