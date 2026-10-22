# Bump Defuddle to 0.19.5 and port its escaping fixes

Status: ready-for-agent
Type: task
Blocked by: - (0.19.5 is eligible under pnpm's minimum-release-age policy from 2026-10-24)

Follow ADR-0003's "on each Defuddle bump" rule:

- Bump `defuddle` to `0.19.5` in `packages/capture`, and update `ENGINE` in `src/page.ts`.
- Diff upstream `src/markdown.ts` between tags `0.19.4` and `0.19.5`, and port the escaping changes into `src/markdown/convert.ts`: `formatMarkdownLinkDestination` with `isDangerousUrl`, `formatMarkdownLinkTitle`, `formatFencedCode`/`formatCodeSpan`, `formatMath`, `formatFootnoteId`, and the wider `escape` override.
- Update the source commit in the file header and in `THIRD_PARTY_NOTICES.md`.

**Done when** `mise run test:golden` passes after reviewing every changed `expected.md` (`-u`), and the escaping cases from the 0.19.5 diff each have a unit test in `test/convert.test.ts`.
