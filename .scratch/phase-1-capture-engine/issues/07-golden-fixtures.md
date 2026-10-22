# Golden fixture corpus (at least 20 pages)

Status: resolved
Type: task
Blocked by: 04

Spec §12.4: `fixtures/pages/<name>/{input.html,url.txt,expected.md,expected-metadata.json}`, a `test:golden` runner (`-u` to update), plus a mise task wrapper. Cover news, personal blogs, documentation, GitHub READMEs, Substack, Medium, recipes, pages with no Open Graph tags, JSON-LD-only pages, lazy images, code-heavy pages, math, and footnotes.

Save snapshots from real pages, but strip tracking scripts and anything personal. The fixtures are public.

## Answer

The user chose **synthetic** fixtures (2026-10-22). They are original HTML modeled on each kind of site's markup, with invented text and names, no tracking scripts, and `*.example` hosts. That replaces the "snapshots from real pages" idea above.

`fixtures/pages/` has 25 pages:
- **Covered:** news (with a cookie banner and a syndicated canonical), personal blogs (Jekyll footnotes, no Open Graph), documentation (an MDN-like sidebar, Sphinx admonitions), a GitHub README, Substack, Medium, a JSON-LD-only recipe, a JSON-LD `@graph`, lazy images, code-heavy, math, Wikipedia-style citations, tables with callouts, `<base href>`, embeds, rich formatting, a short page (low-confidence fallback), Japanese, and German with a long description.
- **Each page has:** `input.html`, `url.txt`, `expected-metadata.json` (link mode, written by hand from §4.2 before the code ran on it), and `expected.md` (page mode).
- **`expected.md`:** generated with `mise run test:golden -u` and then reviewed one by one. The review found the bugs listed in 06.

The runner is `packages/capture/test/golden.test.ts`, run by `mise run test:golden [-u]` (`scripts/verify/golden.sh`). It's also part of `mise run verify`. It requires at least 20 fixtures and both expectations for each one, and it parses every frontmatter as YAML.

Known extraction limitations recorded in the goldens, which are Defuddle's choices rather than ours:
- the subscribe promo strip in `news-cookie-banner` survives
- a byline fragment in `german-magazine-long-description` survives
