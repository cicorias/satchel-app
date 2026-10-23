# Satchel — agent instructions

Satchel saves links and full pages (as Markdown with YAML frontmatter) into storage the user owns: CloudKit first. Surfaces: an iPhone app with a Share Extension and a Safari Web Extension, then Chrome and Edge extensions built from the same WXT codebase.

- **Spec:** `docs/spec.md`. Read it before any non-trivial change.
- **Decisions:** `docs/adr/`, indexed in `docs/adr/README.md`. Never deviate from an ADR silently; write a superseding one.
- **Human-only steps:** `docs/setup/` covers the Apple portal, CloudKit, stores, and signing. Don't guess those values. Write instructions instead.

## Current state

The Phase 0 scaffold is in place, and the delivery order is Phase 0 → 1 (capture engine) → 3 (iPhone) → 2 (Chrome/Edge), per ADR-0011. The packages, the extension, and the Apple targets build and test, but they are placeholders. Open work is in `.scratch/` (start with `.scratch/README.md`).

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
apple/CloudKit/          Satchel.ckdb: the CloudKit schema (source of truth; spec §8.2)
apple/SatchelUITests     UI tests that drive Settings + Safari (Safari extension end to end)
apple/Staged/            gitignored; web build outputs staged for Xcode
art/src/satchel.mjs      artwork design source → art/svg/ masters → PNGs (mise run art)
store/                   rendered store artwork (Chrome, Edge, App Store, GitHub)
site/                    GitHub Pages: landing page, privacy policy, support
scripts/<aspect>/        all task logic: setup, build, verify, deploy, art, ci
.githooks/               pre-commit runs gitleaks
docs/                    spec, ADRs, setup guides, agent config (docs/agents/)
.scratch/                work items: <feature>/spec.md + issues/NN-*.md (committed; ADR-0018)
```

## Commands

Tools are pinned in `mise.toml`. Every task is a one-line wrapper around a script in `scripts/<aspect>/`. Put logic in the script, never inline in `mise.toml` (ADR-0013).

| Command | What it does |
|---|---|
| `mise run setup` | install tools and deps, set up git hooks, generate config |
| `mise run verify` | secrets scan, Biome, typecheck, tests, swift-format lint, SatchelKit tests |
| `mise run verify:web` / `verify:apple` / `verify:shell` | one part only (shell: ShellCheck + bash 3.2 checks) |
| `mise run build` | all web packages and all three extension targets |
| `mise run build:extension [chrome\|edge\|safari]` | one extension target |
| `mise run build:ios` | XcodeGen, then an ad-hoc signed simulator build (no certificate needed; entitlements still apply). `SIGNED=1` for automatic signing |
| `mise run run:ios` | build, install, and launch on a simulator (`SIM="iPhone 18 Pro Max"` by default, `LOGS=1` to stream output) |
| `mise run test:golden [-u]` | golden capture tests over `fixtures/pages/` (`-u` rewrites every `expected.md`; review the diff before committing) |
| `mise run report:capture-timing` | informational `captureLink`/`capturePage` timing over the fixtures (CI prints it; never fails) |
| `mise run test:ios-ui` | UI tests that enable the Safari extension in Settings and open its popup (`ONLY=Class/test`, `VERBOSE=1`) |
| `mise run sim:stop` | stop the app, shut down the simulator, quit DeviceHub/Simulator (`ALL=1` for every simulator) |
| `mise run sim:reset` | uninstall Satchel and erase that simulator (`PRUNE=1` also deletes simulators with missing runtimes) |
| `mise run clean` | remove build outputs (`DEPS=1` also removes node_modules) |
| `mise run apple:project` | regenerate `apple/Satchel.xcodeproj` (skipped when nothing changed; `FORCE=1` always regenerates), then open it in Xcode. Add files on disk and put settings in `project.yml`, because edits made in Xcode's project editor are lost on regenerate |
| `mise run format` | Biome and swift-format, applied in place |
| `mise run art` | re-render every icon and store asset |
| `mise run deploy:ios-archive` / `deploy:ios-upload` | signed archive, then TestFlight upload (see docs/setup/apple.md) |
| `mise run deploy:cloudkit-schema [validate\|import\|export\|diff]` | check, push (Development only), pull, or diff the CloudKit schema in `apple/CloudKit/Satchel.ckdb` with `xcrun cktool` |
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
- Don't use ESLint, Prettier, SwiftLint, fastlane, or npm scripts as task runners. Each was weighed and rejected in an ADR. Shell scripts are bash 3.2-safe; see below.

## Shell scripts (bash 3.2-safe)

Every script in `scripts/` and `.githooks/` is **bash** (not zsh or sh) and must run on **macOS's `/bin/bash` 3.2**. That's what `#!/usr/bin/env bash` resolves to on a stock Mac and in Xcode build phases (ADR-0019).

- Start with `#!/usr/bin/env bash`, `set -euo pipefail`, and `cd "$(dirname "$0")/../.."`. Sourced helpers (e.g. `scripts/run/sim-lib.sh`) have no shebang. Instead, their first line is `# shellcheck shell=bash`.
- **Don't use bash 4+ features:**
  - associative arrays (`declare -A`) or namerefs (`declare -n`, `local -n`)
  - `mapfile` / `readarray`
  - case conversion `${v,,}` / `${v^^}`
  - `|&` or `&>>`
  - `[[ -v name ]]` or `wait -n`
  - negative array indices `${a[-1]}` or `${v@Q}`
  - `shopt -s globstar` / `lastpipe`
- **Empty arrays under `set -u`:** in bash 3.2, `"${arr[@]}"` on an empty array fails with "unbound variable". Branch with if/else instead, or write `${arr[@]+"${arr[@]}"}`.
- **Fill an array from a command's output** with `while IFS= read -r x; do arr+=("$x"); done < <(cmd)`.
- `mise run verify:shell` runs three checks: ShellCheck (`.shellcheckrc`), a grep guard against the constructs above, and, on macOS, `/bin/bash -n` with the real 3.2. It's part of `mise run verify` and both CI jobs. A justified exception to the guard needs a trailing `# bash3-ok <reason>`.

## Agent skills

### Issue tracker

Work items are Markdown files committed under `.scratch/<feature>/` (ADR-0018). GitHub Issues is only for external reports. See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context: one root `GLOSSARY.md` plus `docs/adr/`. See `docs/agents/domain.md`.
