# Third-party notices

Satchel's own code is source-available (see `LICENSE`). It incorporates or is built with the following third-party software, each under its own license. Update this file whenever a runtime dependency is added (spec §12.5).

## Runtime (shipped in the app or extensions)

| Component | License | Used for | Status |
|---|---|---|---|
| [Defuddle](https://github.com/kepano/defuddle) | MIT | content extraction (ADR-0002) | planned for Phase 1 |
| [Turndown](https://github.com/mixmark-io/turndown) | MIT | HTML → Markdown (ADR-0003) | planned for Phase 1 |
| [markdown-it](https://github.com/markdown-it/markdown-it) 15.0.3 | MIT | Markdown rendering (`packages/render`) | in use |
| [markdown-it-footnote](https://github.com/markdown-it/markdown-it-footnote) 4.0.0 | MIT | footnotes in rendered Markdown | in use |
| [DOMPurify](https://github.com/cure53/DOMPurify) 3.4.17 | Apache-2.0 or MPL-2.0 | sanitizing rendered output (`packages/render`) | in use |
| markdown-it's dependencies: [entities](https://github.com/fb55/entities), [linkify-it](https://github.com/markdown-it/linkify-it), [mdurl](https://github.com/markdown-it/mdurl), [uc.micro](https://github.com/markdown-it/uc.micro), [punycode.js](https://github.com/mathiasbynens/punycode.js) | entities: BSD-2-Clause; the rest: MIT | bundled into `render.iife.js` with markdown-it | in use |
| [GRDB.swift](https://github.com/groue/GRDB.swift) | MIT | SQLite local store (ADR-0017) | planned for Phase 3 |

Ported rules (for example, from Defuddle's Turndown configuration or a GFM plugin) keep their original copyright headers in the source files.

## Build-time only (not shipped)

WXT (MIT), Vite (MIT), Turborepo (MIT), TypeScript (Apache-2.0), Vitest (MIT), jsdom (MIT; the test DOM for `packages/render`), Biome (MIT or Apache-2.0), tsup (MIT), resvg-js (MPL-2.0), XcodeGen (MIT), gitleaks (MIT), and ShellCheck (GPL-3.0; run as a separate tool, nothing linked or shipped).
