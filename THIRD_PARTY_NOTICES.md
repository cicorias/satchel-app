# Third-party notices

Satchel's own code is source-available (see `LICENSE`). It incorporates or is built with the following third-party software, each under its own license. Update this file whenever a runtime dependency is added (spec §12.5).

## Runtime (shipped in the app or extensions)

| Component | License | Used for | Status |
|---|---|---|---|
| [Defuddle](https://github.com/kepano/defuddle) 0.19.4 | MIT | content extraction (ADR-0002), bundled into `capture.iife.js`. Its Turndown rules are also ported (see below) | in use |
| [Turndown](https://github.com/mixmark-io/turndown) 7.2.4 | MIT | HTML → Markdown (ADR-0003) | in use |
| [tldts](https://github.com/remusao/tldts) 7.4.19 (with tldts-core) | MIT; bundles the [Public Suffix List](https://publicsuffix.org/) (MPL-2.0) | registrable-domain check in URL normalization (`packages/model`) | in use |
| [@noble/hashes](https://github.com/paulmillr/noble-hashes) 2.4.0 | MIT | SHA-256 for item IDs (`packages/model`) | in use |
| [markdown-it](https://github.com/markdown-it/markdown-it) 15.0.3 | MIT | Markdown rendering (`packages/render`) | in use |
| [markdown-it-footnote](https://github.com/markdown-it/markdown-it-footnote) 4.0.0 | MIT | footnotes in rendered Markdown | in use |
| [DOMPurify](https://github.com/cure53/DOMPurify) 3.4.17 | Apache-2.0 or MPL-2.0 | sanitizing rendered output (`packages/render`) | in use |
| markdown-it's dependencies: [entities](https://github.com/fb55/entities), [linkify-it](https://github.com/markdown-it/linkify-it), [mdurl](https://github.com/markdown-it/mdurl), [uc.micro](https://github.com/markdown-it/uc.micro), [punycode.js](https://github.com/mathiasbynens/punycode.js) | entities: BSD-2-Clause; the rest: MIT | bundled into `render.iife.js` with markdown-it | in use |
| [GRDB.swift](https://github.com/groue/GRDB.swift) | MIT | SQLite local store (ADR-0017) | planned for Phase 3 |

Ported rules keep their original copyright headers in the source files:

- `packages/capture/src/markdown/convert.ts` and `dom.ts` are ported from Defuddle 0.19.4 (`src/markdown.ts`, `src/utils.ts`, `src/utils/dom.ts`, commit `d4c4bad`), under this license:

  > MIT License
  >
  > Copyright (c) 2025 Steph Ango (@kepano)
  >
  > Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
  >
  > The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
  >
  > THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## Build-time only (not shipped)

WXT (MIT), Vite (MIT), Turborepo (MIT), TypeScript (Apache-2.0), Vitest (MIT), jsdom (MIT; the test DOM for `packages/render`), linkedom (ISC; the test DOM for `packages/capture`), yaml (ISC; frontmatter checks in tests), Ajv and ajv-formats (MIT; schema checks in tests), Biome (MIT or Apache-2.0), tsup (MIT), resvg-js (MPL-2.0), XcodeGen (MIT), gitleaks (MIT), and ShellCheck (GPL-3.0; run as a separate tool, nothing linked or shipped).
