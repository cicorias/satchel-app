# Golden fixture corpus (at least 20 pages)

Status: ready-for-agent
Type: task
Blocked by: 04

Spec §12.4: `fixtures/pages/<name>/{input.html,url.txt,expected.md,expected-metadata.json}`, a `test:golden` runner (`-u` to update), plus a mise task wrapper. Cover news, personal blogs, documentation, GitHub READMEs, Substack, Medium, recipes, pages with no Open Graph tags, JSON-LD-only pages, lazy images, code-heavy pages, math, and footnotes.

Save snapshots from real pages, but strip tracking scripts and anything personal. The fixtures are public.
