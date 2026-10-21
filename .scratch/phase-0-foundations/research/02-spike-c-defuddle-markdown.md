# Spike C: Defuddle's Markdown extension points

- **Ticket:** [`../issues/02-spike-c-defuddle-markdown-hooks.md`](../issues/02-spike-c-defuddle-markdown-hooks.md)
- **Date:** 2026-10-21
- **Feeds:** [ADR-0003 addendum](../../../docs/adr/0003-turndown.md), Phase 1 ticket [`06-page-pipeline-and-turndown-rules.md`](../../phase-1-capture-engine/issues/06-page-pipeline-and-turndown-rules.md)
- **Versions examined:** `defuddle@0.19.4` (newest release at least 14 days old; `0.19.5` was published 2026-10-10 and was diffed but can't be installed under pnpm's age policy until 2026-10-24), `turndown@7.2.4`, `turndown@7.2.0` (for fingerprinting), `turndown-plugin-gfm@1.0.2`, `@joplin/turndown-plugin-gfm@1.0.68`, `linkedom@0.18.12`. All were fetched with `npm pack` and read from their published tarballs. The probe ran on Node 24.17.0 with pnpm 11.8.0.

## Question

1. Does Defuddle expose its Markdown conversion in a way we can extend: its Turndown instance, its rules, or an option or hook? We want to add our own rules (image rewriting, figure captions, fenced code with a language, callouts, footnotes, math) and still inherit Defuddle's handling. Which Turndown version does it use, and is that Turndown bundled or a dependency? What do `markdown` and `separateMarkdown` do?
2. Is `turndown-plugin-gfm` still maintained? How do `@joplin/turndown-plugin-gfm` and the other forks compare? What is the latest `turndown`?
3. Should we reuse Defuddle's Turndown setup or run our own Turndown and port the rules? Which GFM plugin should we use, and at which exact versions?

## Summary

- **Defuddle exposes no Turndown instance, rule list, or hook in any entry point.** `createMarkdownContent(html, url)` creates a new `TurndownService` inside the function, adds about 20 rules, and returns a string. The `exports` map blocks deep imports such as `defuddle/dist/markdown.js`. An upstream PR that would expose the rules (`addDefuddleRules`, kepano/defuddle#190) has been open since 2026-03-19 with no review and no longer merges cleanly.
- **The three entry points behave differently.** `defuddle` (the core bundle) has no Markdown support at all and silently ignores `markdown: true`. `defuddle/full` inlines Turndown **7.2.0** and only works when a browser DOM is available. `defuddle/node` `require()`s the external `turndown`, which resolved to **7.2.4** in our probe. The same Defuddle version can therefore produce Markdown through two different Turndown versions.
- **`markdown: true` replaces `content` with Markdown. `separateMarkdown: true` leaves `content` as HTML and adds `contentMarkdown`.** Both work only in `defuddle/full` and `defuddle/node`. Conversion also strips a leading `# H1`. If conversion throws, it returns `"Partial conversion completed with errors. Original HTML:\n\n…"` instead of throwing.
- **Defuddle's Markdown rules change quickly.** `src/markdown.ts` has 33 commits in 2026. The 0.19.4 → 0.19.5 patch rewrote link, title, code, and math escaping and added `isDangerousUrl` filtering. Inheriting these rules means our golden Markdown changes whenever we bump Defuddle, which is what ADR-0003 reason 4 is meant to prevent.
- **Defuddle's rules already cover GFM.** It has its own `table` rule (with a linkedom fallback for the missing `rows` and `cells`), `strikethrough` (`~~`), task-list items, fenced code with a language, callouts, footnotes, and math. It uses no GFM plugin, and neither does the Obsidian Web Clipper.
- **`turndown-plugin-gfm` is unmaintained.** Its last npm release is 1.0.2 (2018-05-11) and its last commit is from 2018. `@joplin/turndown-plugin-gfm@1.0.68` (2026-09-07) is maintained and works with `turndown@7.2.4` when given HTML strings. It is CommonJS only, though, and ships no types. It also contains Joplin-specific behavior, keeps state in module globals, and adds `table` and `strikethrough` rules that would collide with the ported Defuddle rules.
- **Recommendation:** use option (b). Create our own `turndown@7.2.4`. Port Defuddle 0.19.4's `src/markdown.ts` rules into `packages/capture/src/markdown/` with MIT attribution, then change them to match spec §4.5. **Add no GFM plugin dependency**, because the ported rules already cover tables, strikethrough, and task lists. Pin `defuddle@0.19.4` and use the core `defuddle` entry for extraction in both production and tests.

## Findings

### 1. Defuddle's Markdown conversion

**Entry points and exports.** `defuddle@0.19.4/package.json` `exports` defines exactly three subpaths: `"."` → `dist/index.js`, `"./full"` → `dist/index.full.js`, and `"./node"` → `dist/node.js` (import only). It has no `./markdown` and no `./package.json` export. Source: `defuddle@0.19.4/package/package.json`.

| Entry | File (0.19.4) | Exports | Markdown? | Turndown |
|---|---|---|---|---|
| `defuddle` (core, browser UMD) | `dist/index.js`, 338 KB | default `Defuddle` class only (`dist/index.d.ts`) | **No.** The bundle contains no `turndown`, `toMarkdown`, or `createMarkdownContent` code (grep count 0). In the probe, `markdown: true` returned HTML and no `contentMarkdown`. | None |
| `defuddle/full` (browser UMD) | `dist/index.full.js`, 766 KB | default `Defuddle` wrapper plus `createMarkdownContent` (`dist/index.full.d.ts`). Under Node ESM it is reachable only as `default.createMarkdownContent`. The named export declared in the `.d.ts` is `undefined` in Node ESM (probe). | Yes, `toMarkdown()` runs after `parse()` and `parseAsync()` (`src/index.full.ts@0.19.4`). | **Inlined 7.2.0**, using Turndown's browser build. It needs a global `document` with `implementation.createHTMLDocument`. Under Node it failed with `document is not defined`, and with a linkedom global it failed with `createHTMLDocument` undefined. Both failures came back as the "Partial conversion…" string (probe). |
| `defuddle/node` (CJS, from tsc) | `dist/node.js` | `Defuddle(input, url?, options?) → Promise<DefuddleResponse>` and `DefuddleClass` (`dist/node.d.ts`) | Yes. It always calls `parseAsync()` and then `toMarkdown()` (`dist/node.js`). | **External** `require("turndown")` (`dist/markdown.js` line 10). In the probe this resolved to `turndown@7.2.4/lib/turndown.cjs.js`. |

`dist/markdown.js` exists in the tarball, and it exports `createMarkdownContent`, `toMarkdown`, `isGenericElement`, and `asGenericElement`. Because of the `exports` map, Node refuses `import('defuddle/dist/markdown.js')` with `ERR_PACKAGE_PATH_NOT_EXPORTED` (probe). Bundlers that honor `exports` refuse it the same way.

**Is the Turndown instance or its rules reachable?** No. In `src/markdown.ts@0.19.4`, lines 116–135 run `new TurndownService({headingStyle:'atx', hr:'---', bulletListMarker:'-', codeBlockStyle:'fenced', emDelimiter:'*', preformattedCode:true})` inside `createMarkdownContent` and override `escape`. Lines 137–766 then add these rules: `table`, `button`, `list`, `listItem`, `figure`, `image`, `embedToMarkdown`, `highlight`, `strikethrough`, `link`, `complexLinkStructure`, `arXivEnumerate`, `citations`, `footnotesList`, `removals`, `handleTextNodesInTables`, `preformattedCode`, `math`, `katex`, and `callout`. It also calls `keep(['iframe','video','audio','sup','sub','svg','math'])` and `remove(['style','script'])`. The instance never leaves the function, and `DefuddleOptions` has no Markdown option other than the two booleans (`dist/types.d.ts`). Several rules call `turndownService.turndown(...)` recursively through the closure; there are 10 such calls in `src/markdown.ts`. A port has to keep a reference to the instance for those calls.

The only way to reach the instance is to patch `TurndownService.prototype` in `defuddle/node`, which works because that entry uses the shared external `turndown`. The probe's prototype patch saw 8 `turndown()` calls during one parse. This hack does not work in either browser bundle: the core bundle has no Turndown, and the full bundle inlines its own copy. We are not considering it.

**Upstream status.** PR [kepano/defuddle#190](https://github.com/kepano/defuddle/pull/190), "Extract addDefuddleRules for standalone TurndownService usage", was opened 2026-03-19 and is still open, with no comments and `mergeable_state: dirty`. Issue [#105](https://github.com/kepano/defuddle/issues/105) asked for an injectable Markdown processor (PR [#82](https://github.com/kepano/defuddle/pull/82)). It was closed on 2026-02-14, when commit `8c6edc8` ("Add markdown conversion to the full bundle") added `createMarkdownContent` to the full bundle without adding any hook.

**Which Turndown is bundled.** `package.json` lists `turndown: ^7.2.0` under **`optionalDependencies`**, next to `linkedom` and `temml`. `commander` and `mathml-to-latex` are regular dependencies. Upstream's lockfile at tag `0.19.4` pins `node_modules/turndown` to `7.2.0` (source: `package-lock.json@0.19.4`). The inlined copy in `index.full.js` has the 7.2.0 `listItem` body (`t.replace(/^\n+/,"").replace(/\n+$/,"\n").replace(/\n/gm,"\n    ")`), which matches `turndown@7.2.0/lib/turndown.browser.es.js` lines 136–150. It is not the 7.2.1+ version, which uses `trimNewlines` and `' '.repeat(prefix.length)`. 0.19.5 has the same fingerprint. Since `optionalDependencies` resolve to the newest matching version, `defuddle/node` users get 7.2.4 today. In the pnpm probe lockfile, `defuddle@0.19.4` → `turndown: 7.2.4`.

**Result shape** (`dist/types.d.ts`, `src/markdown.ts` lines 993–1003, probe):

- `markdown: true` sets `result.content` to Markdown, and `contentMarkdown` is not set.
- `separateMarkdown: true` leaves `result.content` as the standardized HTML and sets `result.contentMarkdown: string`. If both are set, `markdown` wins (`if/else if`).
- The other keys are the same in all cases: `title, description, domain, favicon, image, language, published, author, site, schemaOrgData, wordCount, parseTime, metaTags`, plus the optional `extractorType, debug, profile, variables`.
- After `turndown()` runs, `createMarkdownContent` also strips a leading `# …` line (lines 956–958), removes empty `[](…)` links, collapses three or more newlines to two, and trims. If conversion throws, it logs to the console and returns `Partial conversion completed with errors. Original HTML:\n\n<html>` (line 989). Its `url` argument is unused.

**Sample output** (`defuddle/node`, `separateMarkdown`, linkedom input; full output in the probe log). The standardized HTML is what we will convert ourselves:

```text
<figure><img src="https://example.com/a.png" alt="Alt A" title="Title A"> <figcaption>Caption with link</figcaption></figure>
<pre><code class="language-python" data-lang="python">…</code></pre>
<div class="callout" data-callout="warning"><div class="callout-title"><div class="callout-title-inner">Warning</div></div> <p>Be careful.</p></div>
<math data-latex="x^2" display="inline" …>…</math>
<sup id="fnref:1"><a href="#fn:1">1</a></sup> … <div id="footnotes"><ol><li id="fn:1">…<a class="footnote-backref" …>↩</a></li></ol></div>
```

Defuddle's Markdown for the same input:

````markdown
![Alt A](https://example.com/a.png)

Caption with link

```python
…
```

> [!warning] Warning
> Be careful.

Inline math $x^2$ here.

| A | B |
| --- | --- |
| 1 | 2 \| pipe |

[^1]: The footnote.
````

Where this differs from Satchel spec §4.5:

- The figure rule drops the image `title`, and its caption is plain text where the spec wants an italic line.
- The figcaption link had already been flattened during extraction. This is the known bug noted in ADR-0002.
- In the probe, `<input type="checkbox">` inside task-list items was removed by standardization, so the `[x]`/`[ ]` state was lost before conversion (`probe-full-output.txt`: `- done`, `- todo`). This happens in extraction, not in Turndown.
- `lang-python` was normalized to `class="language-python" data-lang="python"` by `dist/elements/code.js` (around line 466), so our code-fence rule only has to read `language-*` and `data-lang`.

**Rate of change.** The commit history of `src/markdown.ts` (`gh api repos/kepano/defuddle/commits?path=src/markdown.ts`) shows 33 commits since 2026-01-01. The latest is `7d75992`, "Markdown output escaping (#396)", on 2026-09-26, after 0.19.4 was released. Diffing `dist/markdown.js` between 0.19.4 and 0.19.5 shows these changes in that patch release:

- A new `formatMarkdownLinkDestination`, with `isDangerousUrl` filtering, entity and backslash escaping, and percent-encoding of control characters.
- New `formatMarkdownLinkTitle` HTML-escaping.
- New `formatFencedCode` and `formatCodeSpan`.
- New `formatMath`, which neutralizes `<` and `](` inside `$…$`.
- New `formatFootnoteId`.
- A wider `escape` override.

**Other Defuddle facts that matter for the pipeline.**

- `useAsync` defaults to `true`. With it on, `parseAsync()`, which `defuddle/node` always calls, "may fetch content from third-party APIs" when the local HTML has no content (`README.md` line 198 and the "Third-party services" section; `dist/defuddle.js` lines 661–679). Satchel must pass `useAsync: false` to keep capture on the client (ADR-0006).
- The core bundle uses `math.core` (webpack alias in `webpack.config.js@0.19.4`), which writes `<math data-latex>` from the LaTeX the page already contains. The full and node builds use `math.full`, which adds MathML → LaTeX conversion through `mathml-to-latex` and `temml` (README "Bundles"; `src/elements/math.core.ts@0.19.4`).
- The ported `math` rule's fallback calls `require('mathml-to-latex')` and silently returns `''` when the module is missing (`src/markdown.ts` line 877).

### 2. GFM plugins and Turndown

| Package | Latest (≥14 days old) | Last publish | Repo activity | License | Works with Turndown 7.2.4? |
|---|---|---|---|---|---|
| `turndown` | **7.2.4** | 2026-04-03 (7.2.3 and 7.2.4 published the same day; 7.2.4 reverts PR #515, "Normalize linebreaks within PRE") | [mixmark-io/turndown](https://github.com/mixmark-io/turndown): last push 2026-10-18, last commits are Dependabot merges on 2026-09-03, 154 open issues | MIT | n/a. `engines.node >=18`. Ships CJS, ESM, and UMD, plus browser builds that drop `@mixmark-io/domino` (`turndown@7.2.4/package.json`). |
| `turndown-plugin-gfm` | 1.0.2 | **2018-05-11** | [mixmark-io/turndown-plugin-gfm](https://github.com/mixmark-io/turndown-plugin-gfm): last commit `61a981b` on 2018-05-11, 21 open issues, 13 open PRs, not archived | MIT | Works with string input. **Throws** on a linkedom element (`Cannot read properties of undefined (reading '0')`, because linkedom has no `table.rows`). Emits single-tilde `~x~` strikethrough (probe). Its devDependency is `turndown 4.0.1`. **Unmaintained.** |
| `@joplin/turndown-plugin-gfm` | **1.0.68** | 2026-09-07 | Developed in the Joplin monorepo, [laurent22/joplin `packages/turndown-plugin-gfm`](https://github.com/laurent22/joplin/tree/dev/packages/turndown-plugin-gfm). There, `package.json` already says 1.0.70, which hasn't been published yet. Turndown was bumped to 7.2.4 in #15832 (2026-07-02), and there were real fixes in 2026-03 (#14572, #14653). The npm `repository` field points to [laurent22/joplin-turndown-plugin-gfm](https://github.com/laurent22/joplin-turndown-plugin-gfm), which is **archived** (last push 2021). | MIT | Yes. Its devDependency is `turndown 7.2.4` (`package.json`). With string input, which in Node Turndown parses with domino, it produced a correct table, `[x]`, and `~~x~~` (probe). **Caveats** (from `lib/turndown-plugin-gfm.cjs.js@1.0.68`): CommonJS only, with no ESM build and no types. Complex tables are wrapped in `<div class="joplin-table-wrapper">`. `options_` and `isCodeBlock_` are module-global, so they are shared across `TurndownService` instances. Tables depend on `table.rows` and task items on `node.checked`. When it was given linkedom nodes instead of a string, the table became `AB12` and the checked box became `[ ]` (probe). |
| `@truto/turndown-plugin-gfm` | 1.0.5 | 2026-09-25 | [trutohq/turndown-plugin-gfm](https://github.com/trutohq/turndown-plugin-gfm): 13 stars, last push 2026-10-07 | MIT | `peerDependencies: turndown ^7.0.0`, TypeScript with ESM and types (`npm view`). Not tested. |
| `@bwat47/turndown-plugin-gfm` | 1.1.2 | 2026-10-03 | [bwat47/turndown-plugin-gfm](https://github.com/bwat47/turndown-plugin-gfm): 2 stars, single maintainer, last push 2026-10-03 | MIT | `peerDependencies: turndown ^7.2.4`, TypeScript with ESM and types (`npm view`). Not tested. |
| Defuddle / Obsidian Web Clipper | — | — | — | — | **Neither uses a GFM plugin.** Defuddle's own rules handle tables, strikethrough, and task items (`src/markdown.ts`), and Defuddle's lockfile contains no GFM plugin. The Clipper's `package.json` depends only on `defuddle ^0.19.2`, and it converts with `createMarkdownContent` from `'defuddle/full'` (`src/utils/content-extractor.ts`, `src/utils/filters/markdown.ts`). |

Turndown gives later `addRule` calls precedence: `Rules.add` calls `this.array.unshift(rule)` (`turndown@7.2.4/lib/turndown.browser.es.js` line 271). If we added a GFM plugin on top of the ported Defuddle rules, the two `table` and `strikethrough` rules would shadow each other depending on registration order. Using both adds overlap and buys nothing. In Node, Turndown parses string input with `@mixmark-io/domino` (`lib/turndown.cjs.js` lines 451–475). In browsers it uses the native `DOMParser`. So if we pass Defuddle's `content` string, linkedom never reaches Turndown.

### 3. Options compared

- **(a) Reuse or extend Defuddle's Turndown.** This isn't possible through any supported API. The closest we can get is a "wrap" approach: rewrite the HTML before `createMarkdownContent()` (for example, swap `img[src]` values) and post-process the string afterward. That approach has these problems:
  - We would have to ship the 766 KB full bundle in content scripts and `WKWebView`.
  - We would get Turndown 7.2.0 in the browser but 7.2.4 in Node tests, so tests and production differ.
  - Errors come back as an HTML string instead of being thrown.
  - We couldn't add an image title to figures or italicize captions without fragile regexes.
  - Every Defuddle patch release would change our Markdown.
- **(b) Run our own Turndown and port Defuddle's rules.** This works the same in every environment: one `turndown@7.2.4` and one rule set. Defuddle's standardized HTML contract (`div.callout[data-callout]`, `sup[id^="fnref:"]`, `#footnotes > ol > li[id^="fn:"]`, `math[data-latex]`, `code.language-*[data-lang]`) is exactly what the ported rules consume. The cost is about 1,000 lines of MIT code that we own, plus a diff review of upstream `src/markdown.ts` whenever we bump Defuddle.

## Recommendation

**Use option (b).** Create our own Turndown instance and port Defuddle's rules. Add no GFM plugin dependency.

Pin these exact versions:

| Package | Version | Role |
|---|---|---|
| `defuddle` | `0.19.4` | Extraction only. Import the core `defuddle` entry in production and in Node tests; the core UMD parses linkedom `Document`s (probe). Always pass `useAsync: false`. Don't use `markdown` or `separateMarkdown`. |
| `turndown` | `7.2.4` | Direct dependency. One instance per conversion, built in `packages/capture/src/markdown/`. |
| `@types/turndown` | `5.0.6` (dev) | Types. |
| `linkedom` | `0.18.12` (dev, the version examined; 0.18.13 from 2026-07-07 is also eligible) | Node golden tests. |
| GFM plugin | **none** | Port Defuddle's `table`, `strikethrough`, and `listItem` task-list handling. If a plugin is ever needed, use `@joplin/turndown-plugin-gfm@1.0.68`, passing it HTML strings rather than linkedom nodes. Avoid `turndown-plugin-gfm@1.0.2`. |

Always pass the HTML string (`DefuddleResponse.content`) to `turndown()`, never linkedom nodes. That way Node uses Turndown's own domino parser and browsers use the native `DOMParser`, so tests and production take the same path.

How to port:

- Copy `src/markdown.ts` from tag [`0.19.4`](https://github.com/kepano/defuddle/blob/0.19.4/src/markdown.ts) into `packages/capture/src/markdown/`. Put the Defuddle MIT notice ("Copyright (c) 2025 Steph Ango (@kepano)", from `defuddle@0.19.4/package/LICENSE`) and the source commit `d4c4bad` in the file header and in `THIRD_PARTY_NOTICES`.
- Port the small helpers it imports along with it: `serializeHTML`, `parseHTML`, `isDirectTableChild`, `isTextNode`, and `isElement` from `src/utils/dom.ts` and `src/utils.ts`.
- When 0.19.5 becomes eligible on 2026-10-24, port its escaping changes too (`formatMarkdownLinkDestination` with `isDangerousUrl`, `formatFencedCode`, and `formatMath`). They matter for spec §4.5's "escaping must never mangle URLs or code" and for security.

## Open risks

- **Ported code drifts from upstream.** We lose Defuddle's Markdown fixes unless we look for them. Mitigation: on every Defuddle bump, diff upstream `src/markdown.ts` between the old and new tags and decide which fixes to cherry-pick. Golden tests catch any change in output.
- **Our rules and Defuddle's HTML contract are coupled.** The ported rules depend on Defuddle's standardized markup. If a Defuddle bump changes that markup (callout class names, footnote ids), conversion breaks quietly. Golden fixtures must cover callouts, footnotes, math, code, tables, and figures.
- **Task-list state is lost in extraction.** In the probe, Defuddle 0.19.4 standardization removed `<input type="checkbox">`, and in one case removed the whole list. Spec §4.5 asks for task lists, so Phase 1 must confirm this on real fixtures and, if needed, record the checkbox state as a data attribute before extraction (§4.4 step 2).
- **Math fidelity in the core bundle.** The core bundle only keeps LaTeX that the page already has (`math.core`). Pages that render MathML only, such as MathJax SVG, will have no LaTeX unless we add `mathml-to-latex@1.8.0`. That is the version Defuddle depends on, and it is a regular dependency of the `defuddle` package. If we take it on, we would wire it into the ported `math` rule ourselves. Decide in Phase 1, using fixtures.
- **Defuddle behaviors we must choose to keep or drop:** stripping the leading `# H1`, the `==highlight==` syntax (Obsidian-specific), YouTube and X embeds converted to `![](url)`, tab-indented nested lists, and the "Partial conversion…" fallback. Our port should throw instead.
- **`createMarkdownContent` typings mismatch.** In `defuddle/full` it is typed as a named export, but under Node ESM it is reachable only through `default`. This doesn't matter if we don't use it.
- **The newest Defuddle can't be installed yet.** `0.19.5` is blocked by pnpm's minimum-release-age policy until 2026-10-24. Pinning 0.19.4 now means a deliberate bump later, which is the intended process (ADR-0002).

## Sources

npm metadata (fetched 2026-10-21):

- `npm view defuddle time` (0.19.4: 2026-09-17, 0.19.5: 2026-10-10)
- `npm view turndown time` (7.2.4: 2026-04-03)
- `npm view turndown-plugin-gfm time` (1.0.2: 2018-05-11)
- `npm view @joplin/turndown-plugin-gfm time` (1.0.68: 2026-09-07)
- `npm view @truto/turndown-plugin-gfm`, `npm view @bwat47/turndown-plugin-gfm`
- `npm view linkedom time`, `npm view @types/turndown time`, `npm view mathml-to-latex time`
- `npm search turndown-plugin-gfm`

Package contents (from `npm pack`):

- `defuddle@0.19.4/package/package.json`, `README.md`, `LICENSE`
- `defuddle@0.19.4/package/dist/{index.d.ts,index.full.d.ts,node.d.ts,node.js,markdown.js,markdown.d.ts,types.d.ts,index.js,index.full.js,defuddle.js,elements/code.js,elements/math.js}`
- `defuddle@0.19.5/package/dist/markdown.js` (diffed against 0.19.4)
- `turndown@7.2.4/package/{package.json,lib/turndown.browser.es.js,lib/turndown.cjs.js}`
- `turndown@7.2.0/package/lib/turndown.browser.es.js`
- `turndown-plugin-gfm@1.0.2/package/package.json`
- `@joplin/turndown-plugin-gfm@1.0.68/package/{package.json,lib/turndown-plugin-gfm.cjs.js}`

Source repositories:

- https://github.com/kepano/defuddle/blob/0.19.4/src/markdown.ts
- https://github.com/kepano/defuddle/blob/0.19.4/src/index.full.ts
- https://github.com/kepano/defuddle/blob/0.19.4/src/node.ts
- https://github.com/kepano/defuddle/blob/0.19.4/src/index.ts
- https://github.com/kepano/defuddle/blob/0.19.4/webpack.config.js
- https://github.com/kepano/defuddle/blob/0.19.4/package-lock.json
- https://github.com/kepano/defuddle/blob/0.19.4/src/elements/math.core.ts
- https://github.com/kepano/defuddle/commits/main/src/markdown.ts
- https://github.com/kepano/defuddle/pull/190
- https://github.com/kepano/defuddle/issues/105
- https://github.com/kepano/defuddle/pull/82
- https://github.com/mixmark-io/turndown/releases (v7.2.0 through v7.2.4)
- https://github.com/mixmark-io/turndown-plugin-gfm/commits
- https://github.com/laurent22/joplin/commits/dev/packages/turndown-plugin-gfm
- https://github.com/laurent22/joplin/blob/dev/packages/turndown-plugin-gfm/package.json
- https://github.com/laurent22/joplin-turndown-plugin-gfm (archived)
- https://github.com/obsidianmd/obsidian-clipper/blob/main/package.json
- https://github.com/obsidianmd/obsidian-clipper/blob/main/src/utils/filters/markdown.ts
- https://github.com/obsidianmd/obsidian-clipper/blob/main/src/utils/content-extractor.ts

Probe (outside the repo; scripts and logs are in the session scratchpad):

- `/private/tmp/claude-501/-Users-cicorias-g-cedar-apple-linksaver-satchel/664216f1-a1ee-4cf0-b428-090043feeb6e/scratchpad/spike-c/probe/probe.mjs` and `probe-output.txt`: exports of each entry point, the `markdown` and `separateMarkdown` shapes, deep-import refusal, the full bundle under Node, Turndown resolution, and the GFM plugins under linkedom.
- `/private/tmp/claude-501/-Users-cicorias-g-cedar-apple-linksaver-satchel/664216f1-a1ee-4cf0-b428-090043feeb6e/scratchpad/spike-c/probe/probe-full.mjs` and `probe-full-output.txt`: the full bundle with a linkedom global, compared with `defuddle/node`, plus task-list, nested-list, figure, callout, and math output.
