# ADR-0001: Single repository (monorepo)

- **Status:** Accepted
- **Date:** 2026-10-21

**Context.** The product spans TypeScript (capture engine, renderer, storage adapters, browser extension) and Swift (host apps, Share Extension, Safari extension handler). The capture engine and renderer must be identical across Chrome, Edge, Safari, and the iOS Share Extension. The data model exists in both languages.

**Decision.** Use one repository: pnpm workspaces and Turborepo for TypeScript, and an `apple/` directory holding an XcodeGen-defined project and a local Swift package. Web artifacts flow into Apple targets through a build script, never through copies committed to the repo.

**Consequences.**
- ✅ Atomic changes across model, capture engine, and every client.
- ✅ One CI pipeline and one fixture corpus shared by all platforms.
- ✅ The Safari extension cannot drift from the Chrome/Edge extension.
- ⚠️ Apple builds require the Node toolchain on the Mac.
- ⚠️ CI needs both Ubuntu and macOS runners.

**Alternatives considered.**
- *Separate repositories per platform:* code drift and version juggling between repos.
- *Publishing the capture engine as an npm package consumed by separate repos:* release overhead with no benefit for a solo developer.
- *Nx instead of Turborepo:* more capability than needed.
