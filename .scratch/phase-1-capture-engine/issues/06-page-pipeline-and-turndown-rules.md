# Capture: page pipeline and Turndown rules

Status: resolved
Type: task
Blocked by: 04, ../../phase-0-foundations/issues/02

Spec §4.4 steps 1–8 and §4.5 conventions: clone the DOM, preprocess lazy images, extract with Defuddle, postprocess, convert with Turndown plus our rules, collect `ImageRef`s, assemble frontmatter (§5), and apply the guardrails. Pin `defuddle` and `turndown` exactly.

Spike C has decided (ADR-0003 addendum): **port** Defuddle 0.19.4's `src/markdown.ts` rules into `packages/capture/src/markdown/`, using our own `turndown@7.2.4` and no GFM plugin. Keep the MIT header and update `THIRD_PARTY_NOTICES.md`. Call Defuddle with **`useAsync: false`**. Otherwise it can fetch page content from third-party services, which violates ADR-0006 and §3.2. The addendum lists the §4.5 changes to make to the ported rules and the Defuddle behaviors to decide on. Port the 0.19.5 escaping fixes once that version is eligible (2026-10-24).

## Answer

`capturePage(doc, opts)` in `packages/capture/src/page.ts` runs §4.4 steps 1–8:

1. **Clone.** It works on `doc.cloneNode(true)`, which has no browsing context, so nothing loads or runs. A test checks that the live document is never modified.
2. **Pre-process** (`images.ts` and `code.ts`):
   - Lazy-load attributes are promoted to `src`/`srcset`.
   - The largest `srcset`/`<picture>` candidate wins.
   - Images are recovered from `<noscript>`.
   - Image `src` values become absolute.
   - Code-language hints from GitHub `highlight-source-*` and Sphinx `highlight-*` wrappers become `data-lang`. GitHub's `Box md` README wrapper, which Defuddle read as the language `md`, is neutralized.
3. **Extract** with `defuddle@0.19.4` (core entry), always with `useAsync: false`. A test stubs `fetch` and asserts that it's never called.
4. **Post-process:**
   - Links become absolute (`mailto:`/`tel:` are kept, dangerous schemes stripped).
   - Tracking pixels are dropped.
   - `data:` images over 8 KB are dropped, with a `dropped-large-data-image` warning.
5. **Convert** with our own `turndown@7.2.4` and the rules ported from Defuddle (`src/markdown/`, MIT header, `THIRD_PARTY_NOTICES.md`). The decisions on Defuddle's behaviors are in the second ADR-0003 addendum.
6. **Collect** `ImageRef`s from the final Markdown, in order, once per URL.
7. **Assemble** the §5 frontmatter (`frontmatter.ts`) and the body.
   - Free text in the frontmatter is always double-quoted, and other values stay plain only when YAML reads them back unchanged. The tests and the golden runner parse it with `yaml`.
   - The body starts with `# <title>`. A first heading that repeats the title is dropped.
8. **Guardrails:**
   - Under 50 extracted words, it converts `<main>`, `<article>`, or `<body>` instead, with a `low-confidence-extraction` warning.
   - Over 10 MB, it throws `PageTooLargeError`.
   - A non-http(s) URL throws `UnsupportedUrlError`.

`selectionHtml` converts only the selection (FR-10).

Bugs found while reviewing the golden output and fixed here, with regression tests:
- **List nesting:** nested list items after the first were indented one level too deep. This is an upstream bug in Defuddle 0.19.4.
- **Blank lines in code:** blank lines inside code blocks in list items were deleted.
- **Inline-math spacing:** inline math got a space before punctuation.
- **Blank math:** a text-less `<math data-latex>` was dropped as blank.
- **Heading escapes:** numbered headings were escaped (`## 1\.`).

Other notes:
- **Word count:** it treats Han and kana characters as words (Japanese has no spaces), and reading time uses 230 words or 500 such characters a minute.
- **Version:** `version` now comes from `config/app.config.json`.

Still open: the Defuddle 0.19.5 escaping fixes (ticket 10, from 2026-10-24).
