# Third-party notices

Satchel's own code is source-available (see `LICENSE`). It incorporates or is built with the following third-party software, each under its own license. Update this file whenever a runtime dependency is added (spec §12.5).

## Runtime (shipped in the app or extensions)

| Component | License | Used for | Status |
|---|---|---|---|
| [Defuddle](https://github.com/kepano/defuddle) | MIT | content extraction (ADR-0002) | planned for Phase 1 |
| [Turndown](https://github.com/mixmark-io/turndown) | MIT | HTML → Markdown (ADR-0003) | planned for Phase 1 |
| [markdown-it](https://github.com/markdown-it/markdown-it) | MIT | Markdown rendering | planned for Phase 1 |
| [DOMPurify](https://github.com/cure53/DOMPurify) | Apache-2.0 or MPL-2.0 | sanitizing rendered output | planned for Phase 1 |
| [GRDB.swift](https://github.com/groue/GRDB.swift) | MIT | SQLite local store (ADR-0017) | planned for Phase 3 |

Ported rules (for example, from Defuddle's Turndown configuration or a GFM plugin) keep their original copyright headers in the source files.

## Build-time only (not shipped)

WXT (MIT), Vite (MIT), Turborepo (MIT), TypeScript (Apache-2.0), Vitest (MIT), Biome (MIT or Apache-2.0), tsup (MIT), resvg-js (MPL-2.0), XcodeGen (MIT), and gitleaks (MIT).
