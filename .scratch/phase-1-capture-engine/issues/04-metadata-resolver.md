# Capture: metadata resolver (data islands)

Status: resolved
Type: task
Blocked by: 01

Spec §4.2: `extractMetadata(doc, pageUrl)` with the per-field priority table, JSON-LD rules (invalid JSON → a warning, flattening `@graph`, preferred `@type`s), URL absolutization respecting `<base href>`, and the normalization and truncation rules. Implement `captureLink` on top of it.

**Done when** unit tests with linkedom cover each field's fallback chain, and the first golden fixtures (ticket 07) pass for link mode.

## Answer

`extractMetadata(doc, pageUrl)` is in `packages/capture/src/metadata.ts`, with JSON-LD handling in `json-ld.ts` and the normalizers in `text.ts`. `captureLink` in `index.ts` sits on top of them.

**Tests:**
- `test/metadata.test.ts` (63 tests, linkedom) walks each field's fallback chain.
- It also covers the JSON-LD rules, `<base href>`, normalization, truncation, and the guarantee that the document isn't modified.
- `test/golden.test.ts` runs every `fixtures/pages/*/expected-metadata.json` through `captureLink`.

**Golden fixtures:** `wordpress-yoast-graph`, `news-og-twitter`, and `bare-title-only`. They're synthetic, modeled on Yoast's `@graph`, a news site's OG and Twitter tags with `<base href>` and a broken JSON-LD block, and a bare page. Their expected output was written by hand from §4.2, not generated from the code.

Decisions and gaps for later tickets:
- **No description:** when no source has one, `description` is absent. 05 adds the body excerpt.
- **Entity decoding:** the HTML parser decodes `&name;` forms (semicolon required) in a detached element, after every `<` is escaped, so nothing can become markup. linkedom has no `document.implementation`.
- **Tags searched:** `<meta>` tags are read from the whole document, not just `<head>`, because malformed pages end up with head tags in the body. The key comes from `property` or `name`, case-insensitively.
- **JSON-LD node choice:** the preferred types are ranked in the order §4.2 lists them, so an `Article` beats an earlier `WebPage`. `{"@id": …}` references are followed within the page's JSON-LD, for Yoast's `publisher` and `author`.
- **Skipped values:** an `article:author` that is a URL (usually a Facebook profile) is skipped. Non-http(s) URLs (`data:`, `javascript:`) are skipped for every URL field, so a `data:` favicon falls through to `/favicon.ico`.
- **Dates:** `publishedAt` is normalized to ISO 8601 UTC, and unparseable dates are dropped.
- **Title fallback:** the last-resort title keeps the hostname as given, including `www.`. The `siteName` fallback drops `www.`, per §4.2.
- **Dependency:** `linkedom` is a devDependency (test DOM only).
