# Model: merge rules

Status: resolved
Type: task
Blocked by: 01

Spec §7.3: earliest `createdAt`, page beats link, union of tags, newest note, metadata never overwritten with an empty value, newer body wins (with a 'replace?' flag for the UI).

**Done when** the merge function is pure and every rule has unit tests, including commutativity where the spec implies it.

## Answer

`mergeItems(a, b)` in `packages/model/src/merge.ts` is pure and returns:
- `{ item, body: 'a' | 'b' | 'none', replacesBody }`.
- `replacesBody` is `true` when both sides are page captures. The UI uses it to ask "Replace saved copy?" on a re-save, and sync applies the merge without asking.

`test/merge.test.ts` covers every rule. It also checks:
- **Commutativity:** each of 21 pairs gives the same merged item in either order.
- **Self-merge:** merging an item with itself returns that item unchanged.
- **Purity:** the inputs aren't mutated.

Interpretations of §7.3:
- **"Newer capture"** means `capturedAt`, or `updatedAt` for a link save. An edit after capture, such as a tag change, doesn't make that side's metadata newer.
- **Note:** the side with the later `updatedAt` wins. An *absent* note means "not set by this client", so a re-save from the Share Extension can't wipe it. An empty string is an explicit clear.
- **Fields that follow the body:** `page`, `selection`, and `capturedAt` follow the body winner. `source` comes from the newer capture.
- **`metadataStatus`** is the best of the two (complete > pending > failed), because the merged metadata is at least that complete.
- **Tags:** the union keeps the older side's order, then appends new tags.
- **Ties:** equal timestamps fall back to `updatedAt`, then to the serialized item, so the result never depends on argument order.
- **Unknown fields** from both sides survive. On a clash, the newer capture wins.
