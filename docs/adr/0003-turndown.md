# ADR-0003: Turndown for HTML → Markdown

- **Status:** Accepted
- **Date:** 2026-10-21

**Context.** Defuddle produces clean HTML. We need Markdown with precise control over images (Phase 5 rewrites them to stored asset paths), figures, code fences, tables, and Obsidian-compatible syntax.

**Decision.** Use Turndown (MIT license), pinned to an exact version, with GFM rules and our own custom rules in `packages/capture/src/markdown/`.

**Reasons.**
1. **The de facto standard** HTML-to-Markdown converter in JavaScript, with years of production use. Defuddle's own Markdown output is built on Turndown, so Defuddle's standardized HTML is designed to convert cleanly with it.
2. **Rule-based extensibility.** `addRule`, `keep`, and `remove` cover image rewriting, figure captions, callouts, and code-language detection without forking anything.
3. **Portable.** Runs in browsers and Node against any DOM, with a small bundle and no native dependencies.
4. **Decouples conversion from extraction.** Owning the converter configuration means a Defuddle upgrade cannot silently change our Markdown conventions, and vice versa. Each is pinned and golden-tested independently.

**Implementation note — VERIFY in Phase 0, Spike C.** Check whether Defuddle's full bundle exposes its Markdown conversion or Turndown rules for reuse. If its Turndown instance can be extended with our rules, use it as the base to inherit Defuddle's callout, footnote, and math handling. Otherwise instantiate Turndown directly and port the needed rules (both projects are MIT; keep attribution).

**Risks.** Turndown releases are infrequent, and the original GFM plugin appears stale. → Use the maintained fork or port the rules; golden tests catch regressions.

**Alternatives considered.**
- *unified / rehype-remark:* AST-based and powerful, but a heavier bundle and a larger configuration surface. Overkill unless we later need Markdown AST transforms (for example, highlights); revisit then.
- *node-html-markdown:* fast, but Node-oriented and less flexible for custom rules.
- *Defuddle's `markdown: true` option alone:* simplest, but less control over images and output conventions. Acceptable as an emergency fallback.
