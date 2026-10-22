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

## Addendum (2026-10-22): the port, and the Defuddle behaviors we kept or dropped

Phase 1 ticket 06 ported Defuddle 0.19.4's rules into `packages/capture/src/markdown/convert.ts`, with the MIT header and the full notice in `THIRD_PARTY_NOTICES.md`. These are the decisions Spike C left open:

| Defuddle behavior | Decision | Why |
|---|---|---|
| Strips a leading `# H1` | **Kept.** The body then starts with our own `# <title>`. | One heading per document, always the resolved title. Defuddle usually demotes the article's `<h1>` to `<h2>` anyway. |
| `<mark>` → `==highlight==` | **Dropped.** `<mark>` is kept as inline HTML. | `==` is Obsidian-only. Inline `<mark>` renders in Obsidian, GitHub, and our renderer (`packages/render` allows it). |
| YouTube/X embeds → `![](url)` | **Dropped.** They become a link on its own line: `[YouTube video](https://www.youtube.com/watch?v=…)`, `[Post on X](…)`. Other `<iframe>`, `<video>`, `<audio>`, `<embed>`, and `<object>` become `[Embedded content](src)`, `[Video](src)`, or `[Audio](src)`. | `![](page-url)` is Obsidian's embed syntax. Anywhere else, it's a broken image. |
| Keeps `<iframe>`, `<video>`, `<audio>`, `<svg>`, `<math>` as raw HTML | **Dropped.** Only `<sup>`, `<sub>`, and `<mark>` stay as HTML. Media become links (above), `<svg>` is removed, and `<math>` becomes `$…$`. | Raw embeds in stored Markdown would load third-party content wherever the file is opened. The renderer strips them anyway. |
| Tab-indented nested lists | **Kept.** | It is valid CommonMark, and it is what Obsidian users expect. |
| "Partial conversion…" HTML fallback on error | **Dropped.** Conversion errors throw. | A save should fail loudly, not store HTML labeled as Markdown. |
| Task items need the `task-list-item` class | **Changed.** The checkbox alone marks a task item. | Defuddle 0.19.4 strips the classes but keeps `<input type="checkbox" checked>`. |
| MathML → LaTeX via `mathml-to-latex` | **Not ported.** | The core bundle only keeps LaTeX the page provides (Spike C). Pages with MathML only lose their math; revisit if fixtures show it matters. |

Additional §4.5 changes:
- Figures keep the image title, and the caption becomes an italic line (`_…_` if the caption contains `*`).
- Empty and whitespace-only links are removed.
- `lang-*` classes name the code-fence language, alongside `language-*` and `data-lang`.
- Whitespace-only lines left by stray `<br>`s become blank lines.
- A `<math data-latex>` with no text (which Turndown treats as blank) is still converted.
- `javascript:`, `vbscript:`, `blob:`, and non-image `data:` URLs never become link or image destinations.

The 0.19.5 escaping fixes are still to be ported once that version is eligible (2026-10-24). This is now part of the first Defuddle bump.
