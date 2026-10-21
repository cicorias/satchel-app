# ADR-0013: Tooling — mise, Biome, swift-format, AGENTS.md

- **Status:** Accepted
- **Supersedes:** the ESLint + Prettier choice in spec §12.2
- **Date:** 2026-10-21

## Context

The repo mixes a pnpm/TypeScript workspace with an XcodeGen/Swift project, and is worked on by both a human and coding agents. Tool versions must be reproducible on the Mac and in CI, and the commands for each aspect (setup, build, verify, deploy, art, CI, hooks) need one obvious entry point.

## Decision

- **mise** pins the toolchain: Node 24 LTS, pnpm 11, XcodeGen, gitleaks.
- **mise tasks are thin one-line wrappers.** All logic lives in scripts under `scripts/{setup,build,verify,deploy,art,ci,hooks}/`. No large inline script bodies in `mise.toml`.
- **Biome** for TypeScript/JavaScript/JSON linting and formatting, replacing ESLint + Prettier.
- **swift-format** (bundled with the Xcode toolchain, run as `swift format`) for Swift formatting and linting.
- **`AGENTS.md`** is the canonical agent instructions file. `CLAUDE.md` contains only `@AGENTS.md`.
- Issues are tracked in GitHub Issues; agent guidance for this lives in `docs/agents/`.

## Consequences

- One install step (`mise install`, then `mise run setup`) yields matching tools everywhere.
- Scripts are reviewable, testable, and callable directly by CI without mise if needed.
- Biome is a single fast tool with one config; some ESLint plugin rules have no Biome equivalent.
- swift-format needs no extra install, but has fewer rules than SwiftLint.
- Any agent tool that reads `AGENTS.md` gets the same instructions as Claude Code.

## Alternatives considered

- *ESLint + Prettier:* richer plugin ecosystem, but two tools, slower, more config.
- *SwiftLint:* more rules, but an extra dependency on top of the bundled formatter.
- *npm scripts or a Makefile:* no tool version pinning; Makefiles are awkward for the Swift side.
- *Inline mise tasks:* explicitly rejected by the developer; long shell bodies in TOML are hard to read and review.
