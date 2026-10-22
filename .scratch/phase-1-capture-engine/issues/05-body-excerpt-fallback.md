# Capture: body excerpt fallback

Status: resolved
Type: task
Blocked by: 04

Spec §4.3. Link mode: the first `<p>` with at least 80 characters under article, main, or body, excluding nav, header, footer, aside, and cookie/consent/promo containers. Page mode: the first qualifying paragraph of Defuddle's content (finished in ticket 06).

## Answer

`packages/capture/src/excerpt.ts`:

- **`linkExcerpt(doc)`** is the last step of the link-mode description chain in `extractMetadata`. It finds the first `<p>` of at least 80 characters in `<article>`, then `<main>`, then `<body>`. It skips paragraphs inside `nav`, `header`, `footer`, and `aside`, and inside any element whose class or id matches `/cookie|consent|subscribe|newsletter|promo|banner/i`.
- **`contentExcerpt(container)`** is the page-mode fallback. It comes after Defuddle's description and takes the first paragraph of at least 80 characters from the extracted content.

Decisions:
- **Citation markers:** `<sup>` text is left out of excerpts, so Wikipedia-style "[1]" markers don't end up in descriptions.
- **Sentence-end truncation:** when `truncate` cuts at a sentence end, the ellipsis replaces the full stop: "…Feuerbüchse…", not "…Feuerbüchse.…".

Tests are in `test/page.test.ts` ("body excerpt") and in the `news-cookie-banner`, `blog-no-open-graph`, `docs-sphinx-admonitions`, `wiki-cite-notes`, and `tables-review-callouts` fixtures.
