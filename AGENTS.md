# Satchel — agent instructions

Satchel saves links and full pages (as Markdown with YAML frontmatter) into storage the user owns: CloudKit first. Surfaces: an iPhone app with a Share Extension and a Safari Web Extension, then Chrome and Edge extensions built from the same WXT codebase.

- **Spec:** `docs/spec.md`. Read it before any non-trivial change.
- **Decisions:** `docs/adr/`, indexed in `docs/adr/README.md`. Never deviate from an ADR silently; write a superseding one.
- **Human-only steps:** `docs/setup/` covers the Apple portal, CloudKit, stores, and signing. Don't guess those values. Write instructions instead.

## Current state

The Phase 0 scaffold is in place, and the delivery order is Phase 0 → 1 (capture engine) → 3 (iPhone) → 2 (Chrome/Edge), per ADR-0011. The packages, the extension, and the Apple targets build and test, but they are placeholders. Open work is tracked in GitHub Issues.

## Layout

```
config/app.config.json   single source of truth for names, IDs, and version (CalVer, ADR-0015)
config/local.config.json gitignored: Team ID and other per-machine values (example: local.config.example.json)
packages/model           Item types, URL normalization, IDs, merge rules (spec §7)
packages/capture         capture engine, ESM + IIFE → globalThis.SatchelCapture (spec §4)
packages/render          markdown-it + DOMPurify, ESM + IIFE → globalThis.SatchelRender
packages/storage         StorageProvider contract + CloudKit Web Services adapter (spec §8)
apps/extension           WXT: chrome / edge / safari (MV3), src/entrypoints, src/platform
apple/project.yml        XcodeGen; Satchel (app), SatchelShare, SatchelSafari, WebAssets (aggregate)
apple/SatchelKit         Swift package shared by the app and its extensions
apple/Staged/            gitignored; web build outputs staged for Xcode
art/src/satchel.mjs      artwork design source → art/svg/ masters → PNGs (mise run art)
store/                   rendered store artwork (Chrome, Edge, App Store, GitHub)
site/                    GitHub Pages: landing page, privacy policy, support
scripts/<aspect>/        all task logic: setup, build, verify, deploy, art, ci
.githooks/               pre-commit runs gitleaks
docs/                    spec, ADRs, setup guides, agent config (docs/agents/)
```

## Commands

Tools are pinned in `mise.toml`. Every task is a one-line wrapper around a script in `scripts/<aspect>/`. Put logic in the script, never inline in `mise.toml` (ADR-0013).

| Command | What it does |
|---|---|
| `mise run setup` | install tools and deps, set up git hooks, generate config |
| `mise run verify` | secrets scan, Biome, typecheck, tests, swift-format lint, SatchelKit tests |
| `mise run verify:web` / `verify:apple` | just one half |
| `mise run build` | all web packages and all three extension targets |
| `mise run build:extension [chrome\|edge\|safari]` | one extension target |
| `mise run build:ios` | XcodeGen, then an unsigned simulator build (`SIGNED=1` for automatic signing) |
| `mise run apple:project` | regenerate `apple/Satchel.xcodeproj` only, then open it in Xcode |
| `mise run format` | Biome and swift-format, applied in place |
| `mise run art` | re-render every icon and store asset |
| `mise run deploy:ios-archive` / `deploy:ios-upload` | signed archive, then TestFlight upload (see docs/setup/apple.md) |
| `mise run deploy:extension-zips` | Chrome and Edge store zips |

## Conventions

- Never call `chrome.*` or `browser.*` outside `apps/extension/src/platform/` and the extension entry points.
- Never access `window` or `location` inside `packages/capture`.
- Every new or changed capture rule ships with a fixture (`fixtures/pages/<name>/`).
- No new runtime dependency without a one-line justification in the commit message. pnpm pins exact versions and keeps its minimum-release-age policy; don't add excludes.
- All product identifiers come from `config/app.config.json`. Swift reads them from the `Satchel*` Info.plist keys through `AppEnvironment`, and TypeScript imports the JSON.
- Never commit secrets, the Team ID, API keys, or signing material. They belong in `config/local.config.json`, `~/.appstoreconnect/`, or environment variables. The repo is public (ADR-0014).
- Don't hand-edit generated files: `.xcodeproj`, `apple/*/Info.plist`, `*.entitlements`, `apple/Config/Generated.xcconfig`, WXT `.output/`, `dist/`, or rendered art. Edit the source (`project.yml`, `app.config.json`, `art/src/`) and regenerate.
- Swift: Swift 6 language mode with complete concurrency checking, formatted by swift-format (`.swift-format`), tested with Swift Testing. TypeScript: strict ESM, formatted and linted by Biome, tested with Vitest.
- Commits follow Conventional Commits (`feat(capture): …`, `chore(apple): …`). Commit straight to `main` during scaffolding, then use a branch and PR per milestone.
- Don't use ESLint, Prettier, SwiftLint, fastlane, or npm scripts as task runners. Each was weighed and rejected in an ADR.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for `cicorias/satchel-app`, managed with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context: one root `GLOSSARY.md` plus `docs/adr/`. See `docs/agents/domain.md`.
