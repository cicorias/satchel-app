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

## Addendum — 2026-10-21: Spike C findings

- **Decision: run our own Turndown and port Defuddle's rules.** Reusing Defuddle's Turndown isn't possible: no entry point (`defuddle`, `defuddle/full`, `defuddle/node`) exposes the Turndown instance, its rules, or a hook. `createMarkdownContent()` builds a private `TurndownService` and returns a string, and the `exports` map blocks deep imports. Upstream PR kepano/defuddle#190 (`addDefuddleRules`) has been open, with no review, since 2026-03.
- **The entry points differ.** The core `defuddle` bundle has no Markdown support and ignores `markdown: true`. `defuddle/full` inlines Turndown 7.2.0 and needs a browser DOM. `defuddle/node` uses whatever `turndown` gets installed for its `^7.2.0` optional dependency, which is 7.2.4 today. Reusing Defuddle's conversion would therefore mean different Turndown versions in tests and production, and our Markdown would change with every Defuddle patch release (0.19.5 rewrote link, code, and math escaping).
- **Pin these exact versions:** `defuddle@0.19.4`, used for extraction only through the core `defuddle` entry in both production and Node tests, always with `useAsync: false`. `turndown@7.2.4`. `@types/turndown@5.0.6` (dev). `linkedom@0.18.12` (dev).
- **Use no GFM plugin.** `turndown-plugin-gfm@1.0.2` hasn't been released since 2018. `@joplin/turndown-plugin-gfm@1.0.68` is maintained but CommonJS only, with no types and Joplin-specific behavior. Defuddle's own `table`, `strikethrough`, and task-list `listItem` rules already cover GFM, so we port them. If a plugin is ever needed, use `@joplin/turndown-plugin-gfm@1.0.68` and feed it HTML strings.
- **What Phase 1 ticket 06 needs:**
  - Port `src/markdown.ts` from Defuddle tag `0.19.4` (commit `d4c4bad`) into `packages/capture/src/markdown/`, together with its small DOM helpers. Keep the MIT notice ("Copyright (c) 2025 Steph Ango") in the file header and in `THIRD_PARTY_NOTICES.md`.
  - When 0.19.5 becomes eligible on 2026-10-24, also port its escaping and `isDangerousUrl` changes.
  - Pass Defuddle's `content` HTML string to `turndown()`. Don't pass linkedom nodes.
  - Changes needed to meet §4.5:
    - Keep the image title in figures.
    - Italicize figure captions.
    - Add the image-rewrite hook.
  - Decide whether to keep these Defuddle behaviors:
    - stripping the leading `# H1`
    - `==highlight==`
    - converting embeds to `![](url)`
    - tab-indented nested lists
    - returning the "Partial conversion…" HTML fallback; ours should throw
  - Defuddle 0.19.4 drops task-list checkbox state during extraction, and the core bundle keeps only LaTeX that the page already provides. Cover both with golden fixtures.
- **On each Defuddle bump,** diff upstream `src/markdown.ts` between the two tags and cherry-pick the fixes we want.

Full findings: [Spike C research](../../.scratch/phase-0-foundations/research/02-spike-c-defuddle-markdown.md).
