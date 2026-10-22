# Render: markdown-it + DOMPurify

Status: resolved
Type: task
Blocked by: -

Spec §9.1.4 and §11: render Markdown (including frontmatter handling, footnotes, and callouts) to sanitized HTML, with no scripts, iframes, or event handlers, and a remote-image toggle. Build both ESM and IIFE (`globalThis.SatchelRender`).

**Done when** unit tests include XSS payloads that are neutralized.

## Answer

`packages/render` renders Satchel Markdown to sanitized HTML. The entry point is `src/index.ts`. The markdown-it setup and our own rules are in `markdown.ts`, DOMPurify and the URL policy are in `sanitize.ts`, and frontmatter handling is in `frontmatter.ts`.

**API:** `createRenderer({ window?, html? })` returns `{ render(markdown, options?) }`. `render(markdown, options?)` does the same with a renderer bound to the global `window`, created on first use. `splitFrontmatter(markdown)` and `version` are also exported. Render options are `remoteImages` (default false), `linkTarget` (default `_blank`; `null` omits it), `resolveImage(src)` for stored `images/<hash>.<ext>` paths (§10.4), and `docId` for footnote ids. The result is `{ html, frontmatter, blockedImages }`. The IIFE exposes the same API as `globalThis.SatchelRender` (142 KB minified, 57 KB gzipped).

**Tests:**
- `test/xss.test.ts` (178 tests) runs 79 payloads with inline HTML both on and off. They cover scripts and event handlers, `<iframe>`/`<object>`/`<embed>`, `javascript:` in raw HTML and in Markdown (mixed case, entities, `&colon;`, control characters), `data:text/html`, `<style>`/`<form>`/`<meta>`/`<base>`, MathML and SVG mutation XSS, attribute breakouts, DOM clobbering, malicious frontmatter, and attempts to get around the remote-image toggle (`srcset`, `<picture>`, `poster`, CSS, `//host`).
- Each output goes through `expectSafe` in `test/helpers.ts`. It checks against its own tag, attribute, and URL allowlists, written separately from the sanitizer's, and confirms that re-parsing the output doesn't change it.
- `test/render.test.ts` (53 tests) covers frontmatter, tables, strikethrough, task lists, code fences, footnotes, callouts, math, links, images, inline HTML, and DOM injection.

Decisions:
- **Raw HTML:** inline HTML is passed through by default (`html: true`), because Turndown keeps some tags (`<sup>`, `<sub>`, `<mark>`). DOMPurify then applies an explicit allowlist. SVG, MathML, `style`, forms, media, and embeds are never allowed. A task-list `<input type="checkbox">` is the only input that survives, and it is always `disabled`.
- **URLs:** links may be `http(s)`, `mailto`, `tel`, or `#fragment`. Relative links lose their `href`, because captured links are absolute. External links get `rel="noopener noreferrer"` and `target="_blank"`.
- **Ids:** ids are prefixed `user-content-` (DOMPurify `SANITIZE_NAMED_PROPS`, as GitHub does) and fragment links are rewritten to match, so saved content can't clobber the host page's ids or globals.
- **Remote images:** with `remoteImages` off (the renderer's default, the privacy-safe choice), `http(s)` and protocol-relative images become `<span class="image-blocked" title="url">alt</span>`, and `blockedImages` counts them so the host can offer "Load images". With it on, images load with `referrerpolicy="no-referrer"`, and `//host` is pinned to `https:`. The setting's default for each build is the host's decision (§11, open question 4).
- **Other images:** `data:image/*` (self-contained export) always renders. A relative path renders only through `resolveImage`, and otherwise becomes `image-missing`.
- **Frontmatter:** stripped and returned raw, not parsed. Item fields already come from the model, so no YAML parser is shipped. A block without a closing fence isn't frontmatter.
- **Callouts:** `> [!type][+-] Title` is our own core rule. It renders `<div class="callout" data-callout="type">` with `.callout-title` and `.callout-content`. Foldable callouts use `<details>`/`<summary>`, open with `+`. Without a title, the title is the capitalized type.
- **Math:** `$…$` and `$$…$$` are kept as LaTeX source in `<code class="math math-inline">` and `<pre class="math math-display">`, protected from emphasis parsing. No math engine is shipped. A `$` counts as math only by Pandoc's rules, so prices stay text.
- **Tables:** alignment is written as the `align` attribute, because the sanitizer strips `style`.
- **Linkify:** bare-URL linkification is on. linkify-it is already a markdown-it dependency, and it accounts for about 11 KB of the IIFE.
- **Dependencies:** `markdown-it@15.0.3`, `markdown-it-footnote@4.0.0` (markdown-it org; a local `.d.ts`, because `@types/markdown-it-footnote` targets markdown-it 14's DefinitelyTyped types), and `dompurify@3.4.17`. Task lists, callouts, and math are about 200 lines of our own rules instead of unmaintained plugins. `jsdom@30.1.3` (DOMPurify's documented Node DOM) and `@types/jsdom` are devDependencies.

