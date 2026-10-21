# ADR-0002: Defuddle for content extraction

- **Status:** Accepted
- **Date:** 2026-10-21

**Context.** Page saves must turn an arbitrary page's DOM into the main article content, preserving structure (headings, code, tables, footnotes, math, figures). The extractor must run in browser content scripts, in `WKWebView` on iOS, and in Node for tests.

**Decision.** Use Defuddle (MIT license, TypeScript, by Stephan Ango), pinned to an exact version and wrapped behind our own `extractContent()` interface.

**Reasons.**
1. **Purpose-built for web clipping.** Defuddle is the extraction engine of the Obsidian Web Clipper — the closest existing product to ours — so it is exercised daily on an enormous variety of real-world pages.
2. **Standardized output, not just extraction.** It normalizes footnotes, code blocks, math, headings, and callouts into consistent HTML, so the Markdown conversion step is predictable. Readability returns cleaned HTML but does little normalization.
3. **Less aggressive than Readability.** It is designed to keep borderline content rather than discard it. For an archiving tool, losing content is worse than keeping a little clutter.
4. **Metadata included.** It returns title, author, published date, site, description, image, favicon, and schema.org data, overlapping and backstopping our own resolver (§4.2).
5. **Runs everywhere we need.** A zero-dependency browser bundle for content scripts and `WKWebView`, and `defuddle/node`, which accepts a `Document` from any DOM implementation (linkedom, JSDOM, happy-dom) for fast Node golden tests.

**Risks and mitigations.**
- *Pre-1.0 (0.x versions):* API and output can change between releases. → Exact version pin, golden tests, deliberate upgrades.
- *Small maintainer base:* → The `extractContent()` wrapper allows swapping in Mozilla Readability. Optionally keep a Readability adapter behind a development flag for side-by-side comparison.
- *Known extraction bugs* (for example, inline links inside figure captions are currently flattened). → Track upstream issues and contribute fixes; add local post-processing only when unavoidable.

**Alternatives considered.**
- *Mozilla Readability (Apache-2.0):* mature, powers Firefox Reader View; more aggressive content removal, minimal normalization, limited metadata. Kept as the fallback.
- *Postlight/Mercury Parser:* effectively unmaintained.
- *Hosted "reader" extraction APIs:* violate the client-side capture and privacy principles, cost money per request, and cannot see logged-in content.
- *Writing our own extractor:* years of edge cases already solved elsewhere.
